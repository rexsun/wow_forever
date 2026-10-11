
--[[
    Utility functions.

    `GetViewerFrame(id)` resolves one of Blizzard's four CooldownViewer frames
    from an enum value or a string alias ("CooldownEssential", "BuffIcon", ...).
    It is the last CDM viewer accessor left, and only CDMDataSource uses it —
    for the aura-state keep-alive and for viewer suppression. Nothing in the
    addon renders a viewer child; the trackers own their own pooled buttons.
--]]

local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

---@class private : table
---@field Util util
---@field Pixel table

-- Pixel-snapped layout writes: PixelUtil's four setters, same signatures.
-- Where the engine can round a region's layout itself
-- (SetRoundLayoutToNearestPixel: WoW Forever 1.60.1, reported for 12.1.5),
-- Blizzard deprecates those setters in its favour, so the region gets the flag
-- and a raw write. The flag belongs to one region; that it does not reach its
-- children is inferred (PixelUtil.SetRoundLayoutToNearestPixelRecursively walks
-- them by hand), so it is set on the region being written, on its first write.
-- The setter is IsProtectedFunction: on a protected region in combat it is an
-- ADDON_ACTION_BLOCKED, like the write after it (confirmed in a Forever client).
-- It is skipped there so the helper never adds a blocked call of its own, and
-- the region's next write out of combat sets it. A secret IsProtected (the
-- ObjectSecurity aspect) counts as protected. Without the API (12.1.0),
-- PixelUtil snaps each value.
local Pixel
if UIParent.SetRoundLayoutToNearestPixel then
    local function roundLayout(region)
        if region:GetRoundLayoutToNearestPixel() then return end
        if InCombatLockdown() then
            local protected = region:IsProtected()
            if issecretvalue(protected) or protected then return end
        end
        region:SetRoundLayoutToNearestPixel(true)
    end
    Pixel = {
        SetPoint = function(region, ...) roundLayout(region) region:SetPoint(...) end,
        SetSize = function(region, width, height) roundLayout(region) region:SetSize(width, height) end,
        SetWidth = function(region, width) roundLayout(region) region:SetWidth(width) end,
        SetHeight = function(region, height) roundLayout(region) region:SetHeight(height) end,
    }
else
    Pixel = {
        SetPoint = PixelUtil.SetPoint,
        SetSize = PixelUtil.SetSize,
        SetWidth = PixelUtil.SetWidth,
        SetHeight = PixelUtil.SetHeight,
    }
end
private.Pixel = Pixel

--[[
    blizzard cooldown manager frames in the UIParent
    these are available at any time
    frame names with final 'Viewer' frames are the frame in the UIParent

    EssentialCooldownViewer --show the primary cooldowns, from CooldownSettings (blizzard frame) > tab Spells > Essential Cooldowns
    UtilityCooldownViewer --show the secondary cooldowns, from CooldownSettings (blizzard frame) > tab Spells > Utility Cooldowns
    BuffIconCooldownViewer --show the icons for buff tracker, the buff tracker is CooldownSettings (blizzard frame) > tab Buffs > Tracked BUFFS
    BuffBarCooldownViewer --show time bars for buff tracker, the buff tracker is CooldownSettings (blizzard frame) > tab Buffs > Tracked BARS
--]]

---@alias cooldownviewer_framecategoryname
---|"CooldownEssential"  --essential cooldown viewer
---|"CooldownUtility"  --utility cooldown viewer
---|"BuffIcon"  --buff icon cooldown viewer
---|"BuffBar"  --buff bar cooldown viewer

---@alias cooldownviewer_cooldowntype
---|"Essential"
---|"Utility"
---|"NotDisplayed"

---@alias cooldownviewer_bufftype
---|"BuffIcon"
---|"BuffBar"
---|"NotDisplayed"

---@class enum : table
---@field CooldownViewerCategoryIDs table<cooldownviewer_framecategoryname, number>

private.Enum.CooldownViewerCategoryIDs = {
    CooldownEssential = 0,
    CooldownUtility = 1,
    BuffIcon = 2,
    BuffBar = 3,
}

local cooldownViewerFramesById = {
    [private.Enum.CooldownViewerCategoryIDs.CooldownEssential] = _G["EssentialCooldownViewer"],
    [private.Enum.CooldownViewerCategoryIDs.CooldownUtility] = _G["UtilityCooldownViewer"],
    [private.Enum.CooldownViewerCategoryIDs.BuffIcon] = _G["BuffIconCooldownViewer"],
    [private.Enum.CooldownViewerCategoryIDs.BuffBar] = _G["BuffBarCooldownViewer"],
}

---@class util : table
---@field GetViewerFrame fun(frameId: number|cooldownviewer_framecategoryname|blz_cooldownviewer):blz_cooldownviewer
---@field CDM_COMPONENT_VIEWER_KEYS table<string, cooldownviewer_framecategoryname>
---@field GetComponentViewerKey fun(componentName: string): cooldownviewer_framecategoryname?
---@field GetTrackerOrder fun(settings: table|nil): number[]|nil The icon order a CDM tracker draws on the current spec: its own priority_order_spec list, else the all-specs priority_order
---@field BuildSpellOrderRank fun(componentName: string, spellMap: table<number, true>): table<number, number>|nil Icon-order rank per key: the stored order (GetTrackerOrder) first, Blizzard's CDM order behind it. Reused table — sort with it immediately. Nil for non-CDM components.
---@field SortByOrderRank fun(list: number[], rank: table<number, number>|nil) Sort a spellID array into icon order in place; nil rank = plain spellID order
---@field SyncAnchorProxy fun(container: frame, componentName: string) Mirror a tracker's rect onto its CUE_<viewerKey>Anchor proxy for external addons
---@field GetViewerVisibleSetting fun(viewerKey: cooldownviewer_framecategoryname): number?
---@field ComputeViewerIconLayout fun(settings: viewer_tracker_profile_main, visibleCount?: number, availableWidth?: number): number, number
---@field GetIconZoomCoords fun(iconWidth?: number, iconHeight?: number): number, number, number, number Return icon texcoord values based on the icon_zoom and icon_aspect_ratio profile settings
---@field Color fun(c: number[]): number, number, number, number Unpack a profile {r,g,b,a} color, defaulting a missing alpha to 1
---@field ApplyComponentBackground fun(containerFrame: frame, bgSettings: component_background_profile) Apply or update a background panel behind a component's container frame based on per-component settings
---@field HideComponentBackground fun(containerFrame: frame) Hide the cached background panel for a container frame (if any)
---@field SetComponentEmpty fun(containerFrame: frame, empty: boolean) Mark a container as having no visible content; ApplyComponentBackground will hide the background when true (outside EditMode)
---@field ApplyBarBorder fun(frame: frame, anchorFrame?: frame): frame Apply or remove the global bar border setting to a frame; always returns the overlay frame. anchorFrame overrides which frame the border anchors to (defaults to frame).
---@field GetBarBorderFrame fun(frame: frame): frame? Return the cached border overlay frame for a bar, or nil
---@field ApplyIconBorder fun(button: frame, anchorRegion?: table, color?: number[]): frame Apply or remove the global icon border setting to an icon button; always returns the overlay frame. anchorRegion overrides what the border anchors to (defaults to button) — for buttons whose icon is a sub-rect. color, a per-spell `spell_borders` colour (GetSpellBorderColor), replaces the global colour and draws the border even while the global one is off.
---@field GetSpellBorderColor fun(settings: table|nil, spellID: number|nil): number[]|nil The `spell_borders` colour a tracker or frame saves for a spell, resolved over its base and override ids; nil when none (or a corrupt entry)
---@field GetMissingGlowColor fun(settings: table|nil, spellID: number|nil): number[]|nil The `missing_glow` colour a buff tracker or frame saves for a spell, resolved like GetSpellBorderColor; nil when the spell has no missing glow
---@field ApplyIconVisibility fun(child: frame, hideIcon: boolean) Hide/show the Icon texture and its cached border overlay
---@field CancelIconFade fun(icon: frame) Cancel any in-progress fade animation on an icon
---@field IsIconFading fun(icon: frame): boolean Returns true when an icon has an active fade animation
---@field SetIconAlphaOverride fun(icon: frame, multiplier: number|nil) Set/clear a per-icon alpha multiplier (0..1) that a viewer-child alpha pass multiplies into effectiveAlpha. nil clears the override.
---@field GetIconAlphaOverride fun(icon: frame): number|nil Return the per-icon alpha multiplier or nil
---@field MakeIconVisibilityFilter fun(config: table): function Build an icon_visibility_mode-aware excludeFilter closure for an Additional Frame's adopted icons. config: { getSettingsFn, componentName, isReadyAddonFn? }. Returns a function(icon) -> bool that handles mode-off, hide-instant, and fade.
---@field ApplyIconVisibilityAlpha fun(icon: frame, alpha: number, mode: number|nil) Write an icon's alpha, fading it when icon_visibility_mode is 3 or 5

local getFrameCategoryIdFromCategoryName = function(categoryName)
    local categoryId = private.Enum.CooldownViewerCategoryIDs[categoryName]
    -- Lazy error: `assert`'s message argument is built eagerly on every call
    -- (Lua evaluates all args before the call), so a "never fails" guard still
    -- paid a per-call string concat.  This is on the GetViewerFrame hot path
    -- (thousands of calls/sec via the icon-visibility filter).
    if not categoryId then
        error("getFrameCategoryIdFromCategoryName() Invalid category name: " .. tostring(categoryName) .. " expected one of 'CooldownEssential', 'CooldownUtility', 'BuffIcon', 'BuffBar'")
    end
    return categoryId
end

local lowestCategoryId = 0
local highestCategoryId = 3

local isValidCategoryId = function(categoryId)
    if type(categoryId) == "number" then
        assert(categoryId >= lowestCategoryId and categoryId <= highestCategoryId, "isValidCategoryId() CategoryId is invalid, expected a number between " .. lowestCategoryId .. " and " .. highestCategoryId)
        return true
    end
    error("CategoryId is invalid, expected a number between " .. tostring(lowestCategoryId) .. " and " .. tostring(highestCategoryId))
end

---Returns a human-readable label for a class and optional spec.
---Examples: "Evoker - Devastation", "Warrior", "" (if nothing resolvable).
---@param classFilename string|nil Class file token (e.g. "EVOKER"). Defaults to the player's class.
---@param specIndex number|nil Spec index 1..N for the player's class. Omit for class-only label.
---@return string
function private.GetLocalizedClassSpecLabel(classFilename, specIndex)
    local playerLocalized, playerFile = UnitClass("player")
    local localizedClass
    if classFilename and classFilename ~= playerFile then
        for i = 1, GetNumClasses() do
            local info = C_CreatureInfo.GetClassInfo(i)
            if info and info.classFile == classFilename then
                localizedClass = info.className
                break
            end
        end
        localizedClass = localizedClass or classFilename
    else
        localizedClass = playerLocalized
    end

    if not specIndex or specIndex == 0 then
        return localizedClass or ""
    end
    local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specName then
        return localizedClass or ""
    end
    return (localizedClass or "") .. " - " .. specName
end

---Returns a properly-initialized named Font object, creating it on first use.
---A bare CreateFont() object has no font; DF font helpers (and SetCountdownFont
---consumers) require an initialized one, so we seed it from NumberFontNormal.
---@param name string  global Font object name
---@return Font
local function getOrCreateNamedFont(name)
    local fontObj = _G[name]
    if not fontObj then
        fontObj = CreateFont(name)
        fontObj:CopyFontObject(NumberFontNormal)
    end
    return fontObj
end

---Cache of border overlay frames for ApplyBarBorder.
---One border per target frame; created lazily, shown/hidden on toggle.
---@type table<frame, frame>
local barBorderFrames = {}

---Cache of border overlay frames for ApplyIconBorder.
---One border per icon button; created lazily, shown/hidden on toggle.
---@type table<frame, frame>
local iconBorderFrames = {}

---Module-level icon visibility helper (no per-call closure).
---Hides/shows the Icon texture and its border overlay.
---@param child frame  a CooldownViewer child (child.Icon) or an IconTracker pooled button (child.cue_Icon)
---@param hideIcon boolean
local function applyIconVisibility(child, hideIcon)
    local tex = child.Icon or child.cue_Icon
    if not tex then return end
    tex:SetAlpha(hideIcon and 0 or 1)
    local border = iconBorderFrames[child]
    if border then border:SetShown(not hideIcon) end
end

---Tracks in-flight icon fade animations for icon_visibility_mode.
---Keyed by icon frame reference so iconography state stays off Blizzard tables.
---@type table<frame, AnimationGroup>
local iconFadeAnimations = {}

---Persistent per-icon AnimationGroup reuse pool.  Reused across fade-in /
---fade-out cycles so we don't orphan a stopped AnimationGroup child every
---toggle (WoW frames cannot be destroyed).
---@type table<frame, AnimationGroup>
local iconFadeAnimGroups = {}

---Persistent per-icon Alpha animation reuse pool, paired with iconFadeAnimGroups.
---@type table<frame, Animation>
local iconFadeAnims = {}

---Tracks the current target alpha for an in-flight fade so a repeated request
---to the same target doesn't restart the animation.  Cleared when the fade
---ends or is cancelled.
---@type table<frame, number>
local iconFadeTargetAlpha = setmetatable({}, { __mode = "k" })

-- Forward declarations for icon-visibility-mode helpers (Lua 5.1 upvalue safety).
-- StartIconFade calls CancelIconFade and vice versa; defined together below
-- and exposed via private.Util after the definitions are assigned.
local IsFadeMode
local StartIconFade, CancelIconFade, IsIconFading
local SetIconAlphaOverride, GetIconAlphaOverride

---Per-icon alpha MULTIPLIER (0..1) for icon_visibility_mode.  When set,
---A viewer-child alpha pass multiplies this value into the component-level
---effectiveAlpha for the icon, so component-alpha changes (e.g. visibility-
---rule fade-in/out) compose with the icon-visibility-mode dim factor.
---Hide modes store 0 (fully invisible); fade modes store the configured
---icon_visibility_faded_alpha ratio.  Keyed by icon frame reference with
---weak keys to allow garbage collection.
---@type table<frame, number>
local iconAlphaOverrides = setmetatable({}, { __mode = "k" })

---Tracks icons whose inner textures (Icon/Cooldown) were explicitly zeroed by
---the hide-mode path.  Needed so the next kept-layout pass restores them to
---alpha 1 - skin addons occasionally toggle SetIgnoreParentAlpha on the inner
---regions, breaking the parent->child alpha cascade, so we manage the inner
---alphas directly.
---@type table<frame, boolean>
local iconInnerZeroed = setmetatable({}, { __mode = "k" })

---Zero the inner regions of an addon-owned icon for the hide-mode path.
---
---`Icon` / `Cooldown` are the field names TrinketTracker, ConsumableTracker and
---RacialTracker give their pooled regions; the icon-border overlay is a
---standalone Frame parented to the icon (or, at some call sites, to
---`child.Icon`, which does not propagate alpha to a Frame child), so SetAlpha
---on the icon will not cascade to it and it is hidden directly under both
---keying conventions.
local function zeroInnerTextures(child)
    if child.Icon then child.Icon:SetAlpha(0) end
    if child.Cooldown then child.Cooldown:SetAlpha(0) end
    local border = iconBorderFrames[child]
    if border then border:SetAlpha(0) end
    if child.Icon then
        local iconBorder = iconBorderFrames[child.Icon]
        if iconBorder then iconBorder:SetAlpha(0) end
    end
    iconInnerZeroed[child] = true
end

---Undo zeroInnerTextures.  Glow effects need no handling: glow.root is an
---ordinary child of the icon, so it follows the icon's alpha on its own.
local function restoreInnerTextures(child)
    if not iconInnerZeroed[child] then return end
    if child.Icon then child.Icon:SetAlpha(1) end
    if child.Cooldown then child.Cooldown:SetAlpha(1) end
    local border = iconBorderFrames[child]
    if border then border:SetAlpha(1) end
    if child.Icon then
        local iconBorder = iconBorderFrames[child.Icon]
        if iconBorder then iconBorder:SetAlpha(1) end
    end
    iconInnerZeroed[child] = nil
end

---Cache of background frames for ApplyComponentBackground.
---One background per container frame; created lazily, shown/hidden on toggle.
---@type table<frame, frame>
local componentBgFrames = {}

---Track which rendering mode ("square"|"rounded") each cached background uses.
---When the mode changes, the old frame is hidden and a new one is created.
---@type table<frame, string>
local componentBgModes = {}

---Track the current border_style applied via SetBackdrop on each square-mode
---background frame. SetBackdrop triggers Blizzard's CooldownViewer settings
---notification chain, so we must only call it when the style actually changes
---to avoid recursive Layout → refresh → SetBackdrop → Layout overflow.
---@type table<frame, string>
local componentBgBorderStyle = {}

---Track which container frames currently have no visible content.
---Set by layout functions; checked by ApplyComponentBackground to suppress
---backgrounds when the component is empty (outside EditMode).
---@type table<frame, boolean>
local componentEmptyFrames = {}

local CleanKeybindText -- forward declaration; defined after keyReplacements table

---Cache of spellID → keybind text (or false for "no keybind").
---Wiped on UPDATE_BINDINGS / ACTIONBAR_SLOT_CHANGED via a single watcher frame.
---@type table<number, string|false>
local keybindCache = {}

---Lazily-built map of action slot → raw binding key string.
---Built by scanning known action bar button globals (Blizzard + addon frames).
---Cleared together with keybindCache on UPDATE_BINDINGS / ACTIONBAR_SLOT_CHANGED.
---@type table<number, string>|nil
local slotKeyMap

---Lazily-built map of spellID → raw binding key string. Resolves macro
---buttons that C_ActionBar.FindSpellActionButtons cannot see.
---Cleared together with slotKeyMap on UPDATE_BINDINGS / ACTIONBAR_SLOT_CHANGED.
---@type table<number, string>|nil
local spellKeyMap

---Get the raw binding key for an action bar button frame.
---Checks LAB keyBoundTarget (ElvUI/BT4/Dominos) and Blizzard commandName.
---@param button table
---@return string|nil
local function GetButtonBindingKey(button)
    if button.config and button.config.keyBoundTarget then
        local key = GetBindingKey(button.config.keyBoundTarget)
        if key then return key end
    end
    if button.keyBoundTarget then
        local key = GetBindingKey(button.keyBoundTarget)
        if key then return key end
    end
    if button.commandName then
        local key = GetBindingKey(button.commandName)
        if key then return key end
    end
    return nil
end

---Convert a raw binding key to abbreviated display text.
---@param key string  raw key from GetBindingKey (e.g. "CTRL-SHIFT-BUTTON5")
---@return string
local function FormatBindingKey(key)
    return CleanKeybindText(key)
end

---Build slot→key and spellID→key maps in one pass. Iterates
---LibActionButton-1.0's registry (catches every LAB-based bar addon: ElvUI,
---Bartender4, Dominos, Neuron, RazerNaga, …) plus Blizzard default bars.
---For each button, records the raw binding key under both the action slot
---and the spellID the button actually casts — resolving macros via
---button:GetSpellId() (LAB) or GetMacroSpell() (Blizzard).
---@return table<number, string> slots
---@return table<number, string> spells
local function BuildKeybindMaps()
    local slots = {}
    local spells = {}

    -- Per-spellID candidate ranking: direct spell placements (rank 1) beat
    -- macro wrappers (rank 2); within a rank, lower action slot wins.
    -- Without this, pairs() order over LAB's registry is undefined and a
    -- trinket macro that happens to cast the tracked spell can claim the
    -- binding ahead of a dedicated macro on a different bar.
    local spellCandidates = {}

    local function recordSlot(action, key)
        if action and key and not slots[action] then
            slots[action] = key
        end
    end

    local function recordSpell(spellID, key, rank, slot)
        if not spellID or not key then return end
        local existing = spellCandidates[spellID]
        local slotKey = slot or math.huge
        if not existing
            or rank < existing.rank
            or (rank == existing.rank and slotKey < existing.slot) then
            spellCandidates[spellID] = { key = key, rank = rank, slot = slotKey }
        end
    end

    ---Classify an action slot as rank 1 (direct spell) or rank 2 (macro).
    ---Returns rank and the spellID the slot ultimately casts.
    ---
    ---Midnight reports direct spell placements as `actionType == "macro"` with
    ---`actionID` equal to the spell ID. GetMacroSpell(spellID) returns nil in
    ---that case; fall back to verifying actionID is a real spellID and treat
    ---the placement as rank 1 so it still outranks a real macro wrapper.
    local function classifyAction(action)
        if not action then return 2, nil end
        local actionType, actionID = GetActionInfo(action)
        if actionType == "spell" then
            return 1, actionID
        elseif actionType == "macro" and actionID then
            local macroSpell = GetMacroSpell(actionID)
            if macroSpell then
                return 2, macroSpell
            elseif C_Spell.GetSpellName(actionID) then
                return 1, actionID
            end
        end
        return 2, nil
    end

    -- LAB-based buttons. GetSpellId() correctly returns the cast spell for
    -- both direct placements and macros; we still consult GetActionInfo to
    -- decide rank so direct placements outrank macro wrappers.
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB then
        local buttons = LAB.GetAllButtons and LAB:GetAllButtons() or LAB.buttonRegistry
        if buttons then
            for button in pairs(buttons) do
                if button then
                    local key = GetButtonBindingKey(button)
                    if key then
                        recordSlot(button.action, key)
                        local rank, slotSpellID = classifyAction(button.action)
                        local spellID = slotSpellID
                        if not spellID and button.GetSpellId then
                            spellID = button:GetSpellId()
                        end
                        recordSpell(spellID, key, rank, button.action)
                    end
                end
            end
        end
    end

    -- Blizzard default bars. Same ranking rules so a direct spell placement
    -- on a default bar still outranks a macro wrapper on an addon bar.
    local blizzardBars = {
        "ActionButton", "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton", "MultiBarRightButton",
        "MultiBarLeftButton", "MultiBar5Button",
        "MultiBar6Button", "MultiBar7Button",
    }
    for _, prefix in ipairs(blizzardBars) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button and button.action then
                local key = GetButtonBindingKey(button)
                if key then
                    recordSlot(button.action, key)
                    local rank, spellID = classifyAction(button.action)
                    recordSpell(spellID, key, rank, button.action)
                end
            end
        end
    end

    for spellID, candidate in pairs(spellCandidates) do
        spells[spellID] = candidate.key
    end

    return slots, spells
end

-- ---------------------------------------------------------------------------
-- Item buff duration parsing (locale-safe)
-- ---------------------------------------------------------------------------

---Known spell ID → buff duration (seconds) for on-use trinkets and combat
---potions. Checked before falling back to locale-aware text parsing.
---@type table<number, number>
local KNOWN_BUFF_DURATIONS = {
    -- Midnight raid trinkets (The Voidspire)
    [1259633] = 15,  -- Light Company Guidon
    [1260459] = 15,  -- Vaelgor's Final Stare
    [1258283] = 30,  -- Litany of Lightblind Wrath

    -- Midnight dungeon trinkets
    [1250508] = 15,  -- Emberwing Feather
    [1254624] = 20,  -- Radiant Sunstone
    [1254641] = 15,  -- Rotting Globule
    [1254638] = 15,  -- Solar Core Igniter
    [250766]  = 10,  -- Ampoule of Pure Void
    [250768]  = 45,  -- Echo of L'ura
    [71563]   = 20,  -- Nevermelting Ice Crystal
    [383781]  = 20,  -- Algeth'ar Puzzle Box

    -- Midnight combat potions
    [1236616] = 30,  -- Light's Potential
    [1236998] = 30,  -- Draught of Rampant Abandon
    [1236994] = 30,  -- Potion of Recklessness
    [1238443] = 30,  -- Potion of Zealotry

    -- TWW combat potions
    [431932]  = 30,  -- Tempered Potion
    [431914]  = 20,  -- Potion of Unwavering Focus
}

---Locale-specific patterns that match a numeric duration in spell descriptions.
---Each entry is { secondsPattern, minutesPattern }. The number capture (%d+)
---extracts the duration value regardless of surrounding localised text.
---@type table<string, string[][]>
local DURATION_PATTERNS = {
    enUS = { { "(%d+) sec" }, { "(%d+) min" } },
    enGB = { { "(%d+) sec" }, { "(%d+) min" } },
    deDE = { { "(%d+) Sek" }, { "(%d+) Min" } },
    esES = { { "(%d+) s[^e]", "(%d+) seg" }, { "(%d+) min" } },
    esMX = { { "(%d+) s[^e]", "(%d+) seg" }, { "(%d+) min" } },
    frFR = { { "(%d+) s[^e]", "(%d+) sec" }, { "(%d+) min" } },
    itIT = { { "(%d+) s[^e]", "(%d+) sec" }, { "(%d+) min" } },
    koKR = { { "(%d+)초" }, { "(%d+)분" } },
    ptBR = { { "(%d+) s[^e]", "(%d+) seg" }, { "(%d+) min" } },
    ruRU = { { "(%d+) сек", "(%d+) с[^е]" }, { "(%d+) мин" } },
    zhCN = { { "(%d+)秒" }, { "(%d+)分" } },
    zhTW = { { "(%d+)秒" }, { "(%d+)分" } },
}

---Try locale-aware text patterns to extract a duration from a spell description.
---@param desc string
---@return number?
local function parseDurationFromText(desc)
    local locale = GetLocale()
    local patterns = DURATION_PATTERNS[locale] or DURATION_PATTERNS.enUS

    -- Try seconds patterns
    for _, pat in ipairs(patterns[1]) do
        local seconds = desc:match(pat)
        if seconds then return tonumber(seconds) end
    end
    -- Try minutes patterns
    for _, pat in ipairs(patterns[2]) do
        local minutes = desc:match(pat)
        if minutes then return tonumber(minutes) * 60 end
    end
    return nil
end

---Parse the buff duration (in seconds) from an on-use item's spell.
---Uses a known-duration lookup table first, then falls back to locale-aware
---text parsing of the spell description.
---@param itemID number
---@return number?  duration in seconds, or nil if not parseable
local function parseItemBuffDuration(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID then return nil end

    local known = KNOWN_BUFF_DURATIONS[spellID]
    if known then return known end

    local desc = C_Spell.GetSpellDescription(spellID)
    if desc then
        return parseDurationFromText(desc)
    end
    return nil
end

-- Step color curve for pandemic glow: controls overlay alpha via
-- DurationObject:EvaluateRemainingPercent. Remaining <= 30% → alpha 1 (visible),
-- above 30% → alpha 0 (hidden). Border-style overlays put the animation on a
-- child frame so that SetAlpha(secretAlpha) on the parent controls visibility.
do
    local curve = C_CurveUtil and C_CurveUtil.CreateColorCurve()
    if curve then
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(0.15, CreateColor(1, 0.5, 0, 1))
        curve:AddPoint(0.3, CreateColor(0, 0, 0, 0))
    end
    private.pandemicColorCurve = curve
end

-- ---------------------------------------------------------------------------
-- Keybind text shortening
-- ---------------------------------------------------------------------------

---Replacement table for verbose key names → short display strings.
---@type table<string, string>
local keyReplacements = {
    -- Mouse
    ["MOUSEWHEELUP"] = "MWU",
    ["MOUSEWHEELDOWN"] = "MWD",
    ["MOUSE WHEEL UP"] = "MWU",
    ["MOUSE WHEEL DOWN"] = "MWD",
    ["MIDDLE MOUSE"] = "M3",
    ["BUTTON1"] = "M1",
    ["BUTTON2"] = "M2",
    ["BUTTON3"] = "M3",
    ["BUTTON4"] = "M4",
    ["BUTTON5"] = "M5",
    ["BUTTON6"] = "M6",
    ["BUTTON7"] = "M7",
    ["BUTTON8"] = "M8",
    ["BUTTON9"] = "M9",
    ["BUTTON10"] = "M10",
    ["BUTTON11"] = "M11",
    ["BUTTON12"] = "M12",
    -- Numpad (raw internal names from GetBindingKey)
    ["NUMPAD0"] = "N0",
    ["NUMPAD1"] = "N1",
    ["NUMPAD2"] = "N2",
    ["NUMPAD3"] = "N3",
    ["NUMPAD4"] = "N4",
    ["NUMPAD5"] = "N5",
    ["NUMPAD6"] = "N6",
    ["NUMPAD7"] = "N7",
    ["NUMPAD8"] = "N8",
    ["NUMPAD9"] = "N9",
    ["NUMPADPLUS"] = "N+",
    ["NUMPADMINUS"] = "N-",
    ["NUMPADMULTIPLY"] = "N*",
    ["NUMPADDIVIDE"] = "N/",
    ["NUMPADDECIMAL"] = "N.",
    ["NUMPADEQUALS"] = "N=",
    ["NUMPADENTER"] = "NE",
    -- Other common keys
    ["CAPSLOCK"] = "CL",
    ["SPACE BAR"] = "SP",
    ["SPACEBAR"] = "SP",
    ["SPACE"] = "SP",
    ["BACKSPACE"] = "BS",
    ["DELETE"] = "DL",
    ["INSERT"] = "IN",
    ["HOME"] = "HM",
    ["END"] = "EN",
    ["PAGEUP"] = "PU",
    ["PAGEDOWN"] = "PD",
    ["ESCAPE"] = "ES",
    ["TAB"] = "TB",
    ["PRINTSCREEN"] = "PS",
    ["SCROLLLOCK"] = "SL",
    ["PAUSE"] = "PA",
    ["UP"] = "UP",
    ["DOWN"] = "DN",
    ["LEFT"] = "LT",
    ["RIGHT"] = "RT",
    -- Gamepad triggers & bumpers
    ["PADLTRIGGER"] = "LT",
    ["PADRTRIGGER"] = "RT",
    ["PADLSHOULDER"] = "LB",
    ["PADRSHOULDER"] = "RB",
    -- Gamepad face buttons
    ["PAD1"] = "G1",
    ["PAD2"] = "G2",
    ["PAD3"] = "G3",
    ["PAD4"] = "G4",
    ["PAD5"] = "G5",
    ["PAD6"] = "G6",
    -- Gamepad sticks
    ["PADLSTICK"] = "LS",
    ["PADRSTICK"] = "RS",
    -- Gamepad d-pad
    ["PADDUP"] = "DU",
    ["PADDDOWN"] = "DD",
    ["PADDLEFT"] = "DL",
    ["PADDRIGHT"] = "DR",
    -- Gamepad system
    ["PADFORWARD"] = "FW",
    ["PADBACK"] = "BK",
    ["PADSYSTEM"] = "SYS",
    ["PADPADDLE1"] = "P1",
    ["PADPADDLE2"] = "P2",
    ["PADPADDLE3"] = "P3",
    ["PADPADDLE4"] = "P4",
    -- Gamepad stick directions
    ["PADLSTICKUP"] = "LSU",
    ["PADLSTICKDOWN"] = "LSD",
    ["PADLSTICKLEFT"] = "LSL",
    ["PADLSTICKRIGHT"] = "LSR",
    ["PADRSTICKUP"] = "RSU",
    ["PADRSTICKDOWN"] = "RSD",
    ["PADRSTICKLEFT"] = "RSL",
    ["PADRSTICKRIGHT"] = "RSR",
}

---Shorten a raw keybind string (e.g. "CTRL-SHIFT-BUTTON5") to compact
---display form (e.g. "C-S-M5"). Parses modifiers from the always-English
---raw binding format returned by GetBindingKey, then looks the base key
---up in keyReplacements. Never calls GetBindingText — the output is
---therefore identical across every WoW locale (deDE/frFR/ruRU/zhCN/…).
---@param text string  raw key from GetBindingKey
---@return string
CleanKeybindText = function(text)
    if not text or text == "" then return text end

    local result = text:upper()
    local modifiers = ""

    local changed = true
    while changed do
        changed = false
        if result:find("^CTRL%-") then
            result = result:gsub("^CTRL%-", "", 1)
            modifiers = modifiers .. "C-"
            changed = true
        end
        if result:find("^SHIFT%-") then
            result = result:gsub("^SHIFT%-", "", 1)
            modifiers = modifiers .. "S-"
            changed = true
        end
        if result:find("^ALT%-") then
            result = result:gsub("^ALT%-", "", 1)
            modifiers = modifiers .. "A-"
            changed = true
        end
        if result:find("^META%-") then
            result = result:gsub("^META%-", "", 1)
            modifiers = modifiers .. "M-"
            changed = true
        end
    end

    if keyReplacements[result] then
        result = keyReplacements[result]
    else
        -- Pattern fallbacks for numbered keys not in the explicit table
        -- (BUTTON13..31, extended NUMPAD variants).
        result = result:gsub("^BUTTON(%d+)$", "M%1")
        result = result:gsub("^NUMPAD(%d+)$", "N%1")
    end

    return modifiers .. result
end

-- Party border corner texcoord overrides.
-- UI-Party-Border has rounded left corners (TL, BL) and square right corners (TR, BR).
-- Each variant lists {regionName, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy} entries
-- that override specific corners with mirrored texcoords from the opposite side.
local partyCS, partyCE = 0.0625, 0.9375
local TL_M = {"TopRightCorner", 0.6171875, partyCS, 0.6171875, partyCE, 0.5078125, partyCS, 0.5078125, partyCE}
local TR_M = {"TopLeftCorner", 0.7421875, partyCS, 0.7421875, partyCE, 0.6328125, partyCS, 0.6328125, partyCE}
local BL_M = {"BottomRightCorner", 0.8671875, partyCS, 0.8671875, partyCE, 0.7578125, partyCS, 0.7578125, partyCE}
local BR_M = {"BottomLeftCorner", 0.9921875, partyCS, 0.9921875, partyCE, 0.8828125, partyCS, 0.8828125, partyCE}
local partyCornerOverrides = {
    left = nil,
    right = {TR_M, TL_M, BR_M, BL_M},
    top = {TL_M, BR_M},
    bottom = {TR_M, BL_M},
    all = {TL_M, BL_M},
    tl = {BR_M},
    tr = {TR_M, TL_M, BR_M},
    bl = {TR_M},
    br = {TR_M, BR_M, BL_M},
}

-- One-time-per-container user warning: a protected frame (e.g. a unit frame from
-- an anchoring addon, or a secure component) is anchored to the container, so
-- WoW blocks its resize in combat.  We do NOT swallow the block -- the
-- ADDON_ACTION_BLOCKED plus this message make the misconfiguration visible and
-- actionable.  Secret-safe: reads only the frame name.
local protectedContainerWarned = {}
local function warnProtectedContainer(frame)
    local name = frame:GetName() or "?"
    if protectedContainerWarned[name] then return end
    protectedContainerWarned[name] = true
    private.print(format(
        "%s is anchored to by a protected frame (e.g. a unit frame from an anchoring addon); WoW blocks its resize in combat. Anchor to %sAnchor instead to avoid this.",
        name, name))
end

-- Isolated anchor proxy: a named, always-shown, mouse-disabled frame on
-- UIParent for external addons (unit-frame anchoring tools) to anchor their
-- PROTECTED frames to instead of one of our containers.  Anchoring a protected
-- frame to the container makes the container implicitly protected
-- (anchoree->target), combat-blocking its SetWidth/SetHeight; the proxy absorbs
-- that instead.  It is UIParent-parented and positioned ONLY by absolute
-- UIParent coords mirroring the container's rect -- never anchored to/from or
-- parented to/from the container -- so protection can never cross back.
-- Keyed by the container frame.
local containerProxies = {}
-- Last rect mirrored onto each proxy, so a layout pass that moved nothing
-- writes nothing.  Reused per proxy; never reallocated.
local containerProxyRects = {}

-- Mirror `container`'s screen rect onto its anchor proxy, creating the proxy on
-- first call.  Out of combat only: once an external protected frame anchors to
-- the proxy, the proxy is itself protected and SetPoint/SetSize on it are
-- combat-blocked; the next out-of-combat layout pass catches up.  Coords are
-- read from our own plain container (plain numbers -- never the secret rect of
-- an aura tracker's ResizeToBoundsRect'd bounds frame, which is a CHILD of the
-- component frame this mirrors and is never touched here).
local function syncAnchorProxy(container, proxyName)
    if InCombatLockdown() then
        if container:IsProtected() then warnProtectedContainer(container) end
        return
    end
    local left, bottom = container:GetLeft(), container:GetBottom()
    local w, h = container:GetWidth(), container:GetHeight()
    if not left or not bottom or not w or w <= 0 or h <= 0 then return end
    -- GetLeft/GetBottom/GetWidth/GetHeight are in the container's OWN
    -- (effective-scale-divided) coordinate space, so match the proxy's effective
    -- scale to the container's before applying them; otherwise the proxy desyncs
    -- in BOTH position and size whenever the container is scaled differently
    -- from UIParent (a CUE scale setting, EditMode, or an external scaler).
    -- container:GetEffectiveScale() already folds in UIParent's scale, so the
    -- ratio is the container's own scale relative to UIParent -- 1 when
    -- unscaled, in which case this is a no-op and the raw coords map 1:1.
    local uiScale = UIParent:GetEffectiveScale()
    local cScale = container:GetEffectiveScale()
    local scale = 1
    if uiScale and uiScale > 0 and cScale and cScale > 0 then
        scale = cScale / uiScale
    end
    local proxy = containerProxies[container]
    if not proxy then
        proxy = _G[proxyName] or CreateFrame("Frame", proxyName, UIParent)
        proxy:EnableMouse(false)
        proxy:Show()
        containerProxies[container] = proxy
    end
    local last = containerProxyRects[proxy]
    if not last then
        last = {}
        containerProxyRects[proxy] = last
    elseif last[1] == left and last[2] == bottom and last[3] == w
        and last[4] == h and last[5] == scale then
        return
    end
    last[1], last[2], last[3], last[4], last[5] = left, bottom, w, h, scale
    proxy:SetScale(scale)
    proxy:ClearAllPoints()
    proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    proxy:SetSize(w, h)
end

-- `getViewerChildren` -- the per-frame per-viewer raw-children cache -- lived
-- here.  It existed because `viewer:GetChildren()` is an engine-side allocation
-- (~90 KB per call on a ~10-icon viewer, performance.md "The GetChildren storm")
-- and the combat swipe, layout and membership paths each re-enumerated the same
-- viewer 3-5x per frame.  Every one of those paths went with the 12.1 rework,
-- and its last caller (`CDMDataSource.rebuildAuraState`) went with the keep-alive
-- bridge -- no addon code enumerates a CooldownViewer's children any more.
--
-- If one ever needs to again, restore the cache with it rather than calling
-- GetChildren per consumer; performance.md documents why at length.

---Returns true when icon_visibility_mode is one of the fade-animated variants.
---@param mode number|nil
---@return boolean
IsFadeMode = function(mode)
    return mode == 3 or mode == 5
end

---Cancel any in-progress fade animation on an icon.
---@param icon frame
CancelIconFade = function(icon)
    local ag = iconFadeAnimations[icon]
    if ag then
        ag:Stop()
        iconFadeAnimations[icon] = nil
    end
    iconFadeTargetAlpha[icon] = nil
end

---Set or clear a per-icon alpha override.  When set, the alpha pass applies
---this alpha instead of the component-level effectiveAlpha so an icon faded by
---icon_visibility_mode stays at its faded value across refresh ticks.
---@param icon frame
---@param target number|nil  pass nil to clear
SetIconAlphaOverride = function(icon, target)
    iconAlphaOverrides[icon] = target
end

---Return the per-icon alpha override or nil.
---@param icon frame
---@return number|nil
GetIconAlphaOverride = function(icon)
    return iconAlphaOverrides[icon]
end

---Animate an icon's alpha from its current value to `targetAlpha` over
---`duration` seconds.  Cancels any in-progress fade first.  Idempotent: if the
---icon is already at the target alpha and not animating, this is a no-op.
---@param icon frame
---@param targetAlpha number  final alpha after the fade resolves
---@param duration? number  seconds (default 0.3)
StartIconFade = function(icon, targetAlpha, duration)
    -- Skip restart if we're already animating to the same target (avoids
    -- per-refresh restart spam during the high-frequency CDM refresh path).
    local existing = iconFadeAnimations[icon]
    if existing and iconFadeTargetAlpha[icon] == targetAlpha then return end
    CancelIconFade(icon)
    if not existing and math.abs(icon:GetAlpha() - targetAlpha) < 0.001 then
        return  -- already there, no animation needed
    end
    local ag = iconFadeAnimGroups[icon]
    local fade = iconFadeAnims[icon]
    if not ag then
        ag = icon:CreateAnimationGroup()
        fade = ag:CreateAnimation("Alpha")
        iconFadeAnimGroups[icon] = ag
        iconFadeAnims[icon] = fade
    end
    fade:SetFromAlpha(icon:GetAlpha())
    fade:SetToAlpha(targetAlpha)
    fade:SetDuration(duration or 0.3)
    fade:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        icon:SetAlpha(targetAlpha)
        iconFadeAnimations[icon] = nil
        iconFadeTargetAlpha[icon] = nil
    end)
    iconFadeAnimations[icon] = ag
    iconFadeTargetAlpha[icon] = targetAlpha
    ag:Play()
end

---Returns true when an icon currently has an in-flight fade animation.
---@param icon frame
---@return boolean
IsIconFading = function(icon)
    return iconFadeAnimations[icon] ~= nil
end

--util namespace
private.Util = {

    ---@see getOrCreateNamedFont
    GetOrCreateNamedFont = getOrCreateNamedFont,

    ---@see parseItemBuffDuration
    ParseItemBuffDuration = parseItemBuffDuration,

    ---Return a frame used by the cooldown manager to show icons or bars
    ---Use frameId from private.Enum.CooldownViewerCategoryIDs or from alias cooldownviewer_framecategoryname
    ---Example 1: local essentialFrame = private.Util.GetViewerFrame(private.Enum.CooldownViewerCategoryIDs.CooldownEssential)
    ---Example 2: local essentialFrame = private.Util.GetViewerFrame("CooldownEssential")
    ---This will return the Essential Cooldown Viewer frame
    ---@param frameId number|cooldownviewer_framecategoryname|blz_cooldownviewer
    ---@return blz_cooldownviewer
    GetViewerFrame = function(frameId)
        if (type(frameId) == "table" and frameId.GetItemFrames) then
            --assume it's a cooldown viewer frame already
            return frameId
        end

        if type(frameId) == "string" then
            return cooldownViewerFramesById[getFrameCategoryIdFromCategoryName(frameId)]
        end

        if type(frameId) ~= "number" then
            error("GetViewerFrame() Invalid frameId type: " .. tostring(frameId) .. " expected number or string")
        end

        isValidCategoryId(frameId)

        return cooldownViewerFramesById[frameId]
    end,

    ---Component name (or instance frame_type) → Blizzard CDM viewer key.
    ---Readers: the external anchor proxies (`SyncAnchorProxy`), the icon-order
    ---rank builder (`BuildSpellOrderRank`, the trackers' and the Tracking
    ---tab's), and the one-time `pm.MigrateCDMVisibility`.
    ---No tracker's visibility follows its viewer any more (clamp removed May
    ---2026, e7c571d).
    ---@type table<string, cooldownviewer_framecategoryname>
    CDM_COMPONENT_VIEWER_KEYS = {
        BuffTracker      = "BuffIcon",
        BuffTrackerBars  = "BuffBar",
        CooldownTracker  = "CooldownEssential",
        UtilitiesTracker = "CooldownUtility",
    },

    ---Resolve a component name (including AdditionalFrame_<id> instances) to
    ---its backing CDM viewer key, or nil for non-CDM components / AF
    ---components whose frame_type maps to multiple viewers (e.g. "spells"
    ---spans both CooldownEssential and CooldownUtility — ambiguous).
    ---@param componentName string
    ---@return cooldownviewer_framecategoryname?
    GetComponentViewerKey = function(componentName)
        local direct = private.Util.CDM_COMPONENT_VIEWER_KEYS[componentName]
        if direct then return direct end
        if not componentName or not componentName:match("^AdditionalFrame_") then
            return nil
        end
        local comp = private.ComponentManager and private.ComponentManager.GetComponent(componentName)
        local settings = comp and comp.GetSettings and comp.GetSettings()
        local frameType = settings and settings.frame_type
        if frameType == "buffs" then return "BuffIcon" end
        if frameType == "bar" then return "BuffBar" end
        -- "spells" frame_type spans multiple viewers, so there is no single
        -- proxy name or order rank for it; callers treat nil as "not one of
        -- the four CDM trackers".
        return nil
    end,

    ---Read Blizzard's per-viewer "Always / In Combat / Hidden" CDM setting
    ---directly from the EditMode setting registry. Reads via
    ---`viewer:GetSettingValue` which in turn reads `self.settingMap[setting]`
    ---— independent of the cached `viewer.visibleSetting` field, which addon
    ---code must never touch (writing it taints the viewer; see
    ---`.context/patterns-cooldownviewer.md`).
    ---
    ---Returns nil when the viewer is absent, EditMode is not yet initialized
    ---for it, or the VisibleSetting key is not present in the settingMap.
    ---Returns one of `Enum.CooldownViewerVisibleSetting.Always/InCombat/Hidden`
    ---otherwise.
    ---
    ---Read-only: GetSettingValue does table lookups, no Blizzard-side
    ---mutations, safe to call from any context including combat lockdown.
    ---
    ---Its only reader is pm.MigrateCDMVisibility: nothing else follows this
    ---setting since the May 2026 visibility clamp removal (e7c571d).
    ---@param viewerKey cooldownviewer_framecategoryname
    ---@return number? Enum.CooldownViewerVisibleSetting.Always/InCombat/Hidden, or nil
    GetViewerVisibleSetting = function(viewerKey)
        local viewer = private.Util.GetViewerFrame(viewerKey)
        if not viewer or not viewer.IsInitialized or not viewer.HasSetting or not viewer.GetSettingValue then
            return nil
        end
        if not viewer:IsInitialized() then return nil end
        if not viewer:HasSetting(Enum.EditModeCooldownViewerSetting.VisibleSetting) then return nil end
        return viewer:GetSettingValue(Enum.EditModeCooldownViewerSetting.VisibleSetting)
    end,

    ---Compute icon size and icons-per-row from addon settings only.
    ---Blizzard's viewer.iconLimit is intentionally ignored — it defaults to 1
    ---(from CooldownViewerMixin:OnLoad) and would cap our layout to a single icon.
    ---@param settings viewer_tracker_profile_main
    ---@param visibleCount? number  actual visible icon count; used by max_width auto mode
    ---@param availableWidth? number  actual frame width (e.g. inherited from parent); clamps max_per_row when smaller than settings.width
    ---@return number primaryIconSize
    ---@return number iconsPerRow
    ComputeViewerIconLayout = function(settings, visibleCount, availableWidth)
        local iconOffset = settings.icon_offset or 1
        local xPad = iconOffset
        local profileWidth = settings.width
        local mode = settings.frame_size_mode or "max_width"

        -- When the parent constrains width below settings.width, use the
        -- smaller value so icons-per-row is reduced to fit.
        local constrainedWidth = profileWidth
        if availableWidth and availableWidth > 0 and availableWidth < profileWidth then
            constrainedWidth = availableWidth
        end

        local primaryIconSize, iconsPerRow

        if mode == "max_per_row" then
            -- Explicit per-row count; width is content-driven (not constrained
            -- by settings.width).  Only availableWidth (parent constraint) can
            -- reduce iconsPerRow so icons don't overflow the parent.
            iconsPerRow = math.max(1, settings.max_icons_per_row or 8)
            local rawSize = settings.icon_size or 0
            primaryIconSize = rawSize > 0 and math.floor(rawSize) or 40
            if availableWidth and availableWidth > 0 then
                local fitsInWidth = math.max(1, math.floor((availableWidth + xPad) / (primaryIconSize + xPad)))
                iconsPerRow = math.min(iconsPerRow, fitsInWidth)
            end
        elseif mode == "fixed_width" or mode == "chain_fit" then
            -- Dynamic square icons: fit all visible icons in one row, cap at width/4.
            -- chain_fit is the collapsing-chain [TEST] mode and shares this
            -- sizing exactly; it differs only in that the AuraIconTracker chain
            -- actually APPLIES the result to its buttons (see iconDims).
            local count = math.max(1, visibleCount or 1)
            local maxIconSize = math.floor(constrainedWidth / 4)
            local fittedSize = math.floor((constrainedWidth - xPad * (count - 1)) / count)
            primaryIconSize = math.max(1, math.min(fittedSize, maxIconSize))
            iconsPerRow = count

        elseif mode == "fixed_width_spread" then
            -- Icons at icon_size, spread evenly (gap computed by the caller).
            -- Shrink if too many icons to fit at icon_size.
            local configSize = math.floor(settings.icon_size and settings.icon_size > 0 and settings.icon_size or 40)
            local count = math.max(1, visibleCount or 1)
            local fittedSize = math.floor((constrainedWidth - xPad * (count - 1)) / count)
            primaryIconSize = math.min(configSize, fittedSize)
            primaryIconSize = math.max(1, primaryIconSize)
            iconsPerRow = count

        elseif mode == "fixed_width_stretch" then
            -- Icons stretch horizontally; height = icon_size (width computed by the caller).
            primaryIconSize = math.floor(settings.icon_size and settings.icon_size > 0 and settings.icon_size or 40)
            iconsPerRow = math.max(1, visibleCount or 1)

        else  -- "max_width" (overflow)
            -- max_icons_per_row is intentionally ignored here — overflow mode
            -- fits as many icons as the available width allows.  The setting
            -- only applies to max_per_row mode.
            if settings.icon_size and settings.icon_size > 0 then
                primaryIconSize = math.floor(settings.icon_size)
                iconsPerRow = math.max(1, math.floor((constrainedWidth + xPad) / (primaryIconSize + xPad)))
            else
                -- Auto: fit visible icons in one row (icon size derived from count).
                iconsPerRow = math.max(1, visibleCount or 1)
                primaryIconSize = math.floor((constrainedWidth - xPad * (iconsPerRow - 1)) / iconsPerRow)
            end
        end

        return primaryIconSize, iconsPerRow
    end,

    ---Compute icon size and icons-per-column for vertical tracker layouts.
    ---Mirrors ComputeViewerIconLayout but uses settings.height as the
    ---constraint axis instead of settings.width.  When availableHeight is
    ---provided (from GetInheritedHeight), it overrides settings.height for
    ---fixed-height modes so the layout fills the anchor parent's height.
    ---@param settings viewer_tracker_profile_main
    ---@param visibleCount number
    ---@param availableHeight? number  inherited height from anchor parent
    ---@return number primaryIconSize
    ---@return number iconsPerCol
    ComputeViewerIconLayoutVertical = function(settings, visibleCount, availableHeight)
        local iconOffset = settings.icon_offset or 1
        local yPad = iconOffset
        local profileHeight = settings.height or 150
        local containerHeight = (availableHeight and availableHeight > 0) and availableHeight or profileHeight
        local mode = settings.frame_size_mode or "max_width"

        local primaryIconSize, iconsPerCol

        if mode == "max_per_row" then
            -- Explicit column limit; height is content-driven (not a constraint).
            iconsPerCol = math.max(1, settings.max_icons_per_row or 8)
            local rawSize = settings.icon_size or 0
            primaryIconSize = rawSize > 0 and math.floor(rawSize) or 40

        elseif mode == "fixed_width" or mode == "chain_fit" then
            -- Dynamic square icons: fit all visible in one column, cap at height/4.
            local count = math.max(1, visibleCount or 1)
            local maxIconSize = math.floor(containerHeight / 4)
            local fittedSize = math.floor((containerHeight - yPad * (count - 1)) / count)
            primaryIconSize = math.max(1, math.min(fittedSize, maxIconSize))
            iconsPerCol = count

        elseif mode == "fixed_width_spread" then
            -- Icons at icon_size, spread evenly (gap computed by the caller).
            -- Shrink if too many icons to fit at icon_size.
            local configSize = math.floor(settings.icon_size and settings.icon_size > 0 and settings.icon_size or 40)
            local count = math.max(1, visibleCount or 1)
            local fittedSize = math.floor((containerHeight - yPad * (count - 1)) / count)
            primaryIconSize = math.min(configSize, fittedSize)
            primaryIconSize = math.max(1, primaryIconSize)
            iconsPerCol = count

        elseif mode == "fixed_width_stretch" then
            -- Icons stretch vertically; width = icon_size (height computed by the caller).
            primaryIconSize = math.floor(settings.icon_size and settings.icon_size > 0 and settings.icon_size or 40)
            iconsPerCol = math.max(1, visibleCount or 1)

        else  -- "max_width" (overflow)
            -- Vertical overflow fits as many icons as the available height
            -- allows. max_icons_per_row is intentionally ignored — use
            -- max_per_row mode for an explicit column limit.
            if settings.icon_size and settings.icon_size > 0 then
                primaryIconSize = math.floor(settings.icon_size)
                iconsPerCol = math.max(1, math.floor((containerHeight + yPad) / (primaryIconSize + yPad)))
            else
                iconsPerCol = math.max(1, visibleCount or 1)
                primaryIconSize = math.floor((containerHeight - yPad * (iconsPerCol - 1)) / iconsPerCol)
            end
        end

        return primaryIconSize, iconsPerCol
    end,

    ---Return the current icon texture coordinates based on the icon_zoom and icon_aspect_ratio
    ---profile settings. When iconWidth and iconHeight differ and icon_aspect_ratio is enabled,
    ---adjusts insets to preserve the original square aspect ratio of the icon texture.
    ---@param iconWidth? number  pixel width of the icon frame
    ---@param iconHeight? number  pixel height of the icon frame
    ---@return number left, number right, number top, number bottom
    ---Unpack a profile color table into r, g, b, a.  Alpha defaults to 1: every
    ---shipped default is 4-element, but an imported or hand-edited profile can
    ---drop it, and a nil alpha silently paints nothing.
    ---@param c number[]
    ---@return number r, number g, number b, number a
    Color = function(c)
        return c[1], c[2], c[3], c[4] or 1
    end,

    GetIconZoomCoords = function(iconWidth, iconHeight)
        local keepAspect = private.profile and private.profile.icon_aspect_ratio
        if private.profile and private.profile.icon_zoom then
            local inset = 0.08
            local xInset = inset
            local yInset = inset
            if keepAspect and iconWidth and iconHeight and iconWidth ~= iconHeight then
                local aspectRatio = iconWidth / iconHeight
                if aspectRatio > 1 then
                    yInset = inset + (1 - 1 / aspectRatio) * (0.5 - inset)
                else
                    xInset = inset + (1 - aspectRatio) * (0.5 - inset)
                end
            end
            return xInset, 1 - xInset, yInset, 1 - yInset
        end
        if keepAspect and iconWidth and iconHeight and iconWidth ~= iconHeight then
            local aspectRatio = iconWidth / iconHeight
            if aspectRatio > 1 then
                local yInset = (1 - 1 / aspectRatio) * 0.5
                return 0, 1, yInset, 1 - yInset
            else
                local xInset = (1 - aspectRatio) * 0.5
                return xInset, 1 - xInset, 0, 1
            end
        end
        return 0, 1, 0, 1
    end,

    ---Hide/show the Icon texture and its cached border overlay.
    ---@param child frame  a CooldownViewer child or icon button
    ---@param hideIcon boolean
    ApplyIconVisibility = applyIconVisibility,

    ---Write an icon's alpha, animating the change when `icon_visibility_mode`
    ---is one of the fade variants (3/5) and writing it instantly otherwise.
    ---
    ---The fade used to be implicit in `MakeIconVisibilityFilter`, which is the
    ---only path the CDM viewer children ever took.  The migrated trackers own
    ---plain frames and never touch that filter, so they snapped — the same
    ---setting animated on an AF-routed icon and jumped on its source tracker.
    ---@param icon frame
    ---@param alpha number
    ---@param mode number|nil  settings.icon_visibility_mode
    ApplyIconVisibilityAlpha = function(icon, alpha, mode)
        if IsFadeMode(mode) then
            StartIconFade(icon, alpha, 0.3)
            return
        end
        -- Not a fade mode: a fade left in flight by a mode switch would
        -- otherwise finish and clobber this write.
        if IsIconFading(icon) then CancelIconFade(icon) end
        icon:SetAlpha(alpha)
    end,


    ---Compute the per-item height for a bar layout. When the icon is hidden
    ---(NameOnly / BarOnlyNoName) the item height is driven by barHeight alone;
    ---otherwise it is the max of barHeight and iconSize.
    ---@param barContent string|nil  settings.bar_content string key
    ---@param barHeight number
    ---@param iconSize number
    ---@return number
    ComputeBarItemHeight = function(barContent, barHeight, iconSize)
        if barContent == "NameOnly" or barContent == "BarOnlyNoName" then
            return barHeight
        end
        return math.max(barHeight, iconSize)
    end,


    ---Apply a full font profile (face, size, outline, shadow, position) to a FontString.
    ---Position is only applied when anchor_point is present in the profile,
    ---allowing this to be used for both positioned (addon-owned) and unpositioned
    ---(CooldownViewer-managed) FontStrings.
    ---Shadow is automatically disabled when an outline mode is active, since
    ---outline already provides edge contrast and shadow would be redundant.
    ---@param fontString FontString
    ---@param fontProfile castbar_font_profile
    ---@param parent Region  the region to anchor to (bar, icon, etc.)
    ApplyFontProfile = function(fontString, fontProfile, parent)
        framework:SetFontFace(fontString, fontProfile.font_face)
        framework:SetFontSize(fontString, fontProfile.font_size)
        framework:SetFontOutline(fontString, fontProfile.font_flags)

        local fc = fontProfile.font_color or {1, 1, 1, 1}
        fontString:SetTextColor(fc[1], fc[2], fc[3], fc[4] or 1)

        local hasOutline = fontProfile.font_flags ~= "" and fontProfile.font_flags ~= "NONE"
        local ox = fontProfile.shadow_offset_x or 1
        local oy = fontProfile.shadow_offset_y or -1
        if hasOutline or (ox == 0 and oy == 0) then
            fontString:SetShadowColor(0, 0, 0, 0)
            fontString:SetShadowOffset(0, 0)
        else
            local sc = fontProfile.shadow_color or {0, 0, 0, 1}
            fontString:SetShadowColor(sc[1], sc[2], sc[3], sc[4] or 1)
            fontString:SetShadowOffset(ox, oy)
        end

        if fontProfile.anchor_point then
            fontString:ClearAllPoints()
            Pixel.SetPoint(fontString, fontProfile.anchor_point, parent, fontProfile.anchor_point,
                fontProfile.offset_x or 0, fontProfile.offset_y or 0)
            local pt = fontProfile.anchor_point
            if pt == "TOPLEFT" or pt == "LEFT" or pt == "BOTTOMLEFT" then
                fontString:SetJustifyH("LEFT")
            elseif pt == "TOPRIGHT" or pt == "RIGHT" or pt == "BOTTOMRIGHT" then
                fontString:SetJustifyH("RIGHT")
            else
                fontString:SetJustifyH("CENTER")
            end
        end
    end,

    ---Rotate a fontString 90° for vertical bar orientation.
    ---Only applies the visual rotation; anchor and offsets stay as configured
    ---by ApplyFontProfile so the user can position text freely.
    ---@param fontString fontstring
    ApplyVerticalFontRotation = function(fontString)
        fontString:SetRotation(math.rad(90))
    end,



    ---Convert a raw binding key to abbreviated display text.
    FormatBindingKey = FormatBindingKey,

    ---Resolve a spellID to an abbreviated keybind display string.
    ---Checks action bar slots first, then falls back to direct spell bindings.
    ---Returns the first keybind found, or nil if none.
    ---@param spellID number
    ---@return string|nil
    GetKeybindTextForSpell = function(spellID)
        if not spellID then return nil end

        local cached = keybindCache[spellID]
        if cached ~= nil then
            return cached or nil -- false → nil
        end

        if not slotKeyMap then
            slotKeyMap, spellKeyMap = BuildKeybindMaps()
        end

        -- 1. Direct spellID → key lookup. Covers macros (via GetSpellId /
        --    GetMacroSpell) and direct spell placements in one step.
        local direct = spellKeyMap[spellID]
        if direct then
            local result = FormatBindingKey(direct)
            keybindCache[spellID] = result
            return result
        end

        -- 2. Blizzard action-slot lookup for spells we didn't map above.
        local foundSlots = C_ActionBar.FindSpellActionButtons(spellID)
        if foundSlots then
            for _, slot in ipairs(foundSlots) do
                local key = slotKeyMap[slot]
                if key then
                    local result = FormatBindingKey(key)
                    keybindCache[spellID] = result
                    return result
                end
            end
        end

        -- 3. Fallback: direct spell binding (rare).
        local spellName = C_Spell.GetSpellName(spellID)
        if spellName then
            local key = GetBindingKey("SPELL " .. spellName)
            if key then
                local result = FormatBindingKey(key)
                keybindCache[spellID] = result
                return result
            end
        end

        keybindCache[spellID] = false
        return nil
    end,

    ---Wipe the keybind text cache so the next query re-fetches from Blizzard APIs.
    ---Called automatically on UPDATE_BINDINGS / ACTIONBAR_SLOT_CHANGED.
    InvalidateKeybindCache = function()
        wipe(keybindCache)
        slotKeyMap = nil
        spellKeyMap = nil
    end,

    ---Resolve an itemID to an abbreviated keybind display string.
    ---Tries the item's on-use spell first, then scans action bar slots for the
    ---item placed directly.
    ---@param itemID number
    ---@return string|nil
    GetKeybindTextForItem = function(itemID)
        if not itemID then return nil end

        -- 1. Try spell-based lookup (item's on-use spell on a bar)
        local _, spellID = C_Item.GetItemSpell(itemID)
        if spellID then
            local result = private.Util.GetKeybindTextForSpell(spellID)
            if result then return result end
        end

        -- 2. Scan bound slots for the item placed directly
        if not slotKeyMap then
            slotKeyMap, spellKeyMap = BuildKeybindMaps()
        end
        for slot, key in pairs(slotKeyMap) do
            local actionType, actionID = GetActionInfo(slot)
            if actionType == "item" and actionID == itemID then
                return FormatBindingKey(key)
            end
        end

        return nil
    end,

    ---Apply or update a background panel behind a component's container frame.
    ---Creates a BackdropTemplate frame (square mode) or DF rounded panel (rounded mode)
    ---as a child of the container. Cached per container; mode switches hide the old
    ---frame and create a new one. Hidden when disabled or container has no meaningful size.
    ---@param containerFrame frame  the component's container frame (from GetFrame())
    ---@param bgSettings component_background_profile  the per-component background settings
    ApplyComponentBackground = function(containerFrame, bgSettings)
        if not bgSettings then return end

        local wantMode = bgSettings.rounded and "rounded" or "square"
        local bg = componentBgFrames[containerFrame]
        local currentMode = componentBgModes[containerFrame]

        -- Mode switch: hide old frame, create new one
        if bg and currentMode ~= wantMode then
            bg:Hide()
            componentBgBorderStyle[bg] = nil
            bg = nil
        end

        if not bg then
            if wantMode == "rounded" then
                bg = framework:CreateRoundedPanel(containerFrame, nil, {})
                bg:EnableMouse(false)
            else
                bg = CreateFrame("Frame", nil, containerFrame, "BackdropTemplate")
                bg:EnableMouse(false)
            end
            componentBgFrames[containerFrame] = bg
            componentBgModes[containerFrame] = wantMode
        end

        -- Hide if disabled, container has no meaningful size, or component is empty
        local w, h = containerFrame:GetWidth(), containerFrame:GetHeight()
        if not bgSettings.enabled or w <= 1 or h <= 1
            or (componentEmptyFrames[containerFrame] and not private.isEditMode) then
            bg:Hide()
            return
        end

        -- Position with padding
        local padH = bgSettings.padding_h or bgSettings.padding or 4
        local padV = bgSettings.padding_v or bgSettings.padding or 4
        bg:ClearAllPoints()
        Pixel.SetPoint(bg, "TOPLEFT", containerFrame, "TOPLEFT", -padH, padV)
        Pixel.SetPoint(bg, "BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", padH, -padV)

        -- Strata + level: render behind container content and cross-parented icons
        bg:SetFrameStrata("LOW")
        bg:SetFrameLevel(0)

        -- Apply colors and border style
        local r, g, b, a = unpack(bgSettings.color)
        local borderStyle = bgSettings.border_style or "none"
        local borderColor = bgSettings.border_color or {0, 0, 0, 0.8}
        local br, bg2, bb, ba = unpack(borderColor)
        if wantMode == "rounded" then
            bg:SetColor(r, g, b, a)
            local roundness = bgSettings.roundness or 8
            bg:SetRoundness(16 - roundness)
            if borderStyle == "none" then
                bg:SetBorderCornerColor(0, 0, 0, 0)
            else
                bg:SetBorderCornerColor(br, bg2, bb, ba)
            end
        else
            local partyCorners = borderStyle == "party" and (bgSettings.party_corners or "left") or nil
            local cacheKey = partyCorners and (borderStyle .. ":" .. partyCorners) or borderStyle
            if componentBgBorderStyle[bg] ~= cacheKey then
                componentBgBorderStyle[bg] = cacheKey
                bg.partyCornerOverrides = nil
                if borderStyle == "plain" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
                elseif borderStyle == "slider" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8, insets = {left = 3, right = 3, top = 3, bottom = 3}})
                elseif borderStyle == "tooltip" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
                elseif borderStyle == "dialog" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = {left = 11, right = 12, top = 12, bottom = 11}})
                elseif borderStyle == "dialog_gold" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = {left = 11, right = 12, top = 12, bottom = 11}})
                elseif borderStyle == "achievement_wood" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", tileEdge = true, edgeSize = 32})
                elseif borderStyle == "chat_bubble" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\ChatBubble-Backdrop", edgeSize = 16})
                elseif borderStyle == "toast" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border", tile = true, tileEdge = true, tileSize = 12, edgeSize = 12, insets = {left = 5, right = 5, top = 5, bottom = 5}})
                elseif borderStyle == "party" then
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\CharacterFrame\\UI-Party-Border", tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = {left = 32, right = 32, top = 32, bottom = 32}})
                    bg.partyCornerOverrides = partyCornerOverrides[partyCorners]
                    if not bg.partyCornerHooked then
                        bg.partyCornerHooked = true
                        hooksecurefunc(bg, "SetupTextureCoordinates", function(self)
                            local overrides = self.partyCornerOverrides
                            if not overrides then return end
                            for _, entry in ipairs(overrides) do
                                local region = self[entry[1]]
                                if region then
                                    region:SetTexCoord(entry[2], entry[3], entry[4], entry[5], entry[6], entry[7], entry[8], entry[9])
                                end
                            end
                        end)
                    end
                    -- Apply overrides immediately (hook only fires on subsequent resizes)
                    local overrides = bg.partyCornerOverrides
                    if overrides then
                        bg:SetupTextureCoordinates()
                    end
                else
                    bg:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                end
            end
            if borderStyle ~= "none" then
                bg:SetBackdropBorderColor(br, bg2, bb, ba)
            end
            bg:SetBackdropColor(r, g, b, a)
        end

        bg:Show()
    end,

    ---Hide the cached background panel for a container frame (if any).
    ---@param containerFrame frame
    HideComponentBackground = function(containerFrame)
        local bg = componentBgFrames[containerFrame]
        if bg then bg:Hide() end
    end,

    ---Mark a container as having no visible content.
    ---ApplyComponentBackground will hide the background when true (outside EditMode).
    ---@param containerFrame frame
    ---@param empty boolean
    SetComponentEmpty = function(containerFrame, empty)
        componentEmptyFrames[containerFrame] = empty or nil
    end,

    ---Apply or remove the global bar border setting to a frame.
    ---Creates a separate overlay frame at a higher frame level so the border is
    ---visible above the bar's status bar textures (which cover the full frame area
    ---and would hide a backdrop edge applied directly to the bar).
    ---When `inside` is false (default), the overlay is offset by 1px outward so
    ---the edge surrounds the bar. When `inside` is true, the overlay is flush
    ---with the bar bounds and the 1px edges overlap the bar content.
    ---The frame is always kept alive and shown (even when borders are disabled) so
    ---that bar text FontStrings parented to it remain visible above the bar fill.
    ---@param frame frame
    ---@param anchorFrame frame? Optional frame to anchor the border to (defaults to frame)
    ---@return frame overlayFrame
    ApplyBarBorder = function(frame, anchorFrame)
        local border = barBorderFrames[frame]
        if not border then
            -- Plain Frame instead of BackdropTemplate — BackdropTemplate does Lua
            -- arithmetic on GetSize() in SetupTextureCoordinates, which fails on
            -- secret-number frame dimensions during combat (cast bar fade animations).
            -- Four ColorTexture edges avoid the issue: C rendering handles secret dims.
            border = CreateFrame("Frame", nil, frame)

            local edges = {}
            for i = 1, 4 do
                local tex = border:CreateTexture(nil, "OVERLAY")
                edges[i] = tex
            end
            edges[1]:SetPoint("TOPLEFT")
            edges[1]:SetPoint("TOPRIGHT")
            Pixel.SetHeight(edges[1], 1)
            edges[2]:SetPoint("BOTTOMLEFT")
            edges[2]:SetPoint("BOTTOMRIGHT")
            Pixel.SetHeight(edges[2], 1)
            -- Vertical edges fit between horizontal edges to avoid corner overlap
            edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
            edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
            Pixel.SetWidth(edges[3], 1)
            edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
            edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
            Pixel.SetWidth(edges[4], 1)
            border.edges = edges

            barBorderFrames[frame] = border
        end
        border:SetFrameLevel(frame:GetFrameLevel() + 5)

        local settings = private.profile.bar_border
        local size = settings.size or 1

        -- Update edge thickness
        Pixel.SetHeight(border.edges[1], size)
        Pixel.SetHeight(border.edges[2], size)
        Pixel.SetWidth(border.edges[3], size)
        Pixel.SetWidth(border.edges[4], size)

        -- Update anchor offsets: outside = beyond frame by border size, inside = flush with frame
        local inside = settings.inside
        local offset = inside and 0 or size
        anchorFrame = anchorFrame or frame
        border:ClearAllPoints()
        Pixel.SetPoint(border, "TOPLEFT", anchorFrame, "TOPLEFT", -offset, offset)
        Pixel.SetPoint(border, "BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", offset, -offset)

        if settings.enabled then
            local r, g, b, a = unpack(settings.color)
            for _, edge in ipairs(border.edges) do
                edge:SetColorTexture(r, g, b, a)
                edge:Show()
            end
        else
            for _, edge in ipairs(border.edges) do
                edge:Hide()
            end
        end
        border:Show()
        return border
    end,

    ---Return the cached border overlay frame for a bar, or nil if not yet created.
    ---@param frame frame
    ---@return frame?
    GetBarBorderFrame = function(frame)
        return barBorderFrames[frame]
    end,

    ---Apply or remove the global icon border setting to an icon button.
    ---Creates a border overlay frame on first call (four ColorTexture edges),
    ---then shows/hides edges based on the icon_border profile setting.
    ---The overlay is a child of the button with two-point anchoring, so it
    ---auto-resizes when the icon is resized via SetSize().
    ---When `inside` is true, the border is drawn flush with the icon bounds.
    ---A per-spell `color` (GetSpellBorderColor) takes the global colour's place
    ---and draws the border even while `icon_border.enabled` is off; size and
    ---inside stay global.
    ---@param button frame  an icon button (CooldownViewer child, trinket icon, consumable icon, etc.)
    ---@param anchorRegion table?  region to anchor the border to (defaults to button); use it when the icon is only a sub-rect of the button, as on the bar trackers
    ---@param color number[]?  {r, g, b, a}: this spell's own border colour
    ---@return frame overlayFrame  the border overlay frame
    ApplyIconBorder = function(button, anchorRegion, color)
        local border = iconBorderFrames[button]
        if not border then
            border = CreateFrame("Frame", nil, button)

            local edges = {}
            for i = 1, 4 do
                local tex = border:CreateTexture(nil, "OVERLAY")
                edges[i] = tex
            end
            edges[1]:SetPoint("TOPLEFT")
            edges[1]:SetPoint("TOPRIGHT")
            Pixel.SetHeight(edges[1], 1)
            edges[2]:SetPoint("BOTTOMLEFT")
            edges[2]:SetPoint("BOTTOMRIGHT")
            Pixel.SetHeight(edges[2], 1)
            -- Vertical edges fit between horizontal edges to avoid corner overlap
            edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
            edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
            Pixel.SetWidth(edges[3], 1)
            edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
            edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
            Pixel.SetWidth(edges[4], 1)
            border.edges = edges

            iconBorderFrames[button] = border
        end
        border:SetFrameLevel(button:GetFrameLevel())

        local settings = private.profile.icon_border
        local size = settings.size or 1

        -- Update edge thickness
        Pixel.SetHeight(border.edges[1], size)
        Pixel.SetHeight(border.edges[2], size)
        Pixel.SetWidth(border.edges[3], size)
        Pixel.SetWidth(border.edges[4], size)

        -- Update anchor offsets: outside = beyond frame by border size, inside = flush with frame
        local inside = settings.inside
        local offset = inside and 0 or size
        anchorRegion = anchorRegion or button
        border:ClearAllPoints()
        Pixel.SetPoint(border, "TOPLEFT", anchorRegion, "TOPLEFT", -offset, offset)
        Pixel.SetPoint(border, "BOTTOMRIGHT", anchorRegion, "BOTTOMRIGHT", offset, -offset)

        if settings.enabled or color then
            local r, g, b, a = unpack(color or settings.color)
            for _, edge in ipairs(border.edges) do
                edge:SetColorTexture(r, g, b, a)
                edge:Show()
            end
        else
            for _, edge in ipairs(border.edges) do
                edge:Hide()
            end
        end
        border:Show()
        return border
    end,
}

-- Expose icon-visibility-mode helpers via private.Util after definitions are
-- assigned to the forward-declared locals.
private.Util.ApplyIconVisibility = applyIconVisibility
private.Util.CancelIconFade = CancelIconFade
private.Util.IsIconFading = IsIconFading
private.Util.SetIconAlphaOverride = SetIconAlphaOverride
private.Util.GetIconAlphaOverride = GetIconAlphaOverride
private.Util.RestoreInnerTextures = restoreInnerTextures

---Scan `list` for `id`.  Passed to ResolveBySpellIdentity as a file-scope
---function so the membership test allocates no closure per call.
---@param id number
---@param list number[]
---@return true|nil  nil rather than false, so the identity walk keeps going
local function listContainsId(id, list)
    for i = 1, #list do
        if list[i] == id then return true end
    end
    return nil
end

---Resolve a per-spell lookup across a CDM entry's whole identity: the spell
---itself first, then its base spell, then the remaining members (override +
---linked).  First non-nil result wins.
---
---**Only `icon_overrides` may use this.** The linked half of the walk is
---live-verified necessary there (see ResolveIconOverride) and actively WRONG
---for routing and per-spell settings — use ResolveByBaseOrOverride for those.
---Linked ids are 1:N and are what tell talent-swap variants apart, and
---`resolvedIdentity` is keyed by base spellID, so the two Outbreak variants
---(same `spellID`, different `linkedSpellIDs`) collide onto one set: expanding
---a routing query over it makes configuring one variant capture its sibling.
---A texture is the one thing where that collision is harmless — both variants
---are the same spell to the eye, which is exactly what the user picked an icon
---for.
---
---`ctx` is threaded through to `fn` so callers pass a file-scope function
---instead of allocating a closure per call.
---@generic T, C
---@param spellID number
---@param fn fun(id: number, ctx: C): T|nil
---@param ctx C|nil
---@return T|nil
local function resolveBySpellIdentity(spellID, fn, ctx)
    local v = private.Util.ResolveByBaseOrOverride(spellID, fn, ctx)
    if v ~= nil then return v end
    -- Same no-forced-build rule as ResolveByBaseOrOverride.
    if not private.CDMDataSource.IsResolved() then return nil end
    local base = private.CDMDataSource.GetIdentityOwner(spellID) or spellID
    local ids = private.CDMDataSource.GetAuraIdentitySet(base)
    if ids then
        for id in pairs(ids) do
            if id ~= spellID and id ~= base then
                v = fn(id, ctx)
                if v ~= nil then return v end
            end
        end
    end
    return nil
end

---A spell's rank ("Rank 3") where the client has spell ranks (WoW Forever):
---its subtext, kept only when it carries a number.  Retail subtexts ("Racial",
---"Shapeshift") carry none, so every rank feature is inert there by data, with
---no client check.  The subtext is "" until the spell's data has loaded.
---ponytail: a digit stands in for "is a rank" in every locale; a numbered
---non-rank subtext would pass too.  A rank flag, if the API ever grows one.
---@param spellID number
---@return string|nil
private.Util.SpellRank = function(spellID)
    local subtext = C_Spell.GetSpellSubtext(spellID)
    if subtext and subtext:find("%d") then return subtext end
    return nil
end

---The number in a rank label ("Rank 3" -> 3), for ordering a spell's ranks.
---@param rank string
---@return number
private.Util.RankNumber = function(rank)
    return tonumber(rank:match("%d+")) or 0
end

---Resolve a per-spell lookup over a spell's BASE and OVERRIDE ids only: the
---spell itself, then the base of the CDM entry it belongs to, then that entry's
---`overrideSpellID`.  First non-nil result wins.
---
---**This is the rule that makes a base spellID and an overrideSpellID behave
---the same in every downstream API,** and it has to exist because the two are
---written and read by different halves of the same feature.  The Options
---pickers key their entries by `overrideSpellID or spellID` — that is the id
---Blizzard's own item frames display, so it is the id the user picked — while a
---cooldown tracker's map key is the plain `spellID` (`resolvedSpellID[id]`) and
---the aura trackers key by whichever identity member the live aura carries.  A
---raw table or list lookup on either side silently misses whenever a tracked
---spell has an override, and the feature does nothing at all.
---
---Stops short of linked ids ON PURPOSE.  Base↔override is 1:1 inside one
---cooldownID — the two ids name the same thing.  Base↔linked is 1:N and is the
---only thing distinguishing talent-swap variants, so walking it here would let
---a setting on one variant leak onto its sibling (`resolvedIdentity` collides
---them onto a single set).  See `.context/patterns-cooldownviewer.md`.
---
---A non-CDM key (a trinket slotID, a consumable category id, a custom spell)
---has no entry, so the walk collapses to the plain `fn(spellID, ctx)` plus two
---nil-returning table lookups.
---@generic T, C
---@param spellID number
---@param fn fun(id: number, ctx: C): T|nil
---@param ctx C|nil
---@return T|nil
private.Util.ResolveByBaseOrOverride = function(spellID, fn, ctx)
    local v = fn(spellID, ctx)
    if v ~= nil then return v end
    -- Never FORCE the resolved-category build from here.  Routing queries reach
    -- this during component enable on PLAYER_LOGIN, while CDMDataSource waits
    -- for LOADING_SCREEN_DISABLED to initialize — building against a client with
    -- no CDM data yet used to cache an empty model for the whole session.  The
    -- plain own-key lookup above is still correct; identity resolution simply
    -- starts working once the model exists.
    if not private.CDMDataSource.IsResolved() then return nil end
    local base = private.CDMDataSource.GetIdentityOwner(spellID) or spellID
    if base ~= spellID then
        v = fn(base, ctx)
        if v ~= nil then return v end
    end
    local override = private.CDMDataSource.GetOverrideSpellID(base)
    if override and override ~= spellID then
        return fn(override, ctx)
    end
    return nil
end

---The colour `map` holds under `id`, when it is one.  File-scope for the same
---no-closure reason as listContainsId.
---@param id number
---@param map table
---@return number[]|nil
local function borderColorIn(id, map)
    local c = map[id]
    if type(c) == "table" and type(c[1]) == "number" then return c end
    return nil
end

---A spell's own icon border colour (`spell_borders`, set from the Tracking tab's
---row menu), resolved over base and override like every per-spell setting: the
---tab keys an entry by its row, the tracker by its map key.  Runs per button on
---the icon trackers' layout pass, so an empty map returns before the walk.
---@param settings table|nil  a tracker's or frame's settings
---@param spellID number|nil
---@return number[]|nil
private.Util.GetSpellBorderColor = function(settings, spellID)
    local map = settings and settings.spell_borders
    if not spellID or type(map) ~= "table" or next(map) == nil then return nil end
    return private.Util.ResolveByBaseOrOverride(spellID, borderColorIn, map)
end

---A spell's missing-buff glow colour (`missing_glow`, set from the Tracking
---tab's row menu): an entry turns the glow on, its value is the colour.  Same
---resolution as GetSpellBorderColor; runs per cell on the always-show layout pass.
---@param settings table|nil  a buff tracker's or `buffs` frame's settings
---@param spellID number|nil
---@return number[]|nil
private.Util.GetMissingGlowColor = function(settings, spellID)
    local map = settings and settings.missing_glow
    if not spellID or type(map) ~= "table" or next(map) == nil then return nil end
    return private.Util.ResolveByBaseOrOverride(spellID, borderColorIn, map)
end

---The manual `icon_overrides` texture for a tracked spell, resolved from a
---tracker's MAP KEY rather than from a viewer child's `cooldownInfo`.
---
---The deleted `ApplyIconOverride`/`ApplyBarIconOverride` were the
---CooldownViewer-child path: they read `info.overrideSpellID or info.spellID` off
---the frame.  The migrated trackers have no child — their icons are addon-owned
---regions keyed by spellID — so they lost the feature entirely in the migration
---and need this instead (found 2026-08-17; see
---`.context/migration-parity-gaps.md`).
---
---Both identity walks are load-bearing, not defensive.  A saved entry is keyed
---by `info.overrideSpellID or info.spellID` (what the retired Icon Overrides
---picker wrote) or by a Tracking-tab row's own key (`TrackingModel.SetIconOverride`
---keys a new one so), and a tracker's map key
---can be a DIFFERENT member of the same CDM entry, in either direction:
---  * **down** — a cooldown tracker keys by `info.spellID`
---    (`resolvedSpellID[id] = info.spellID`), so a spell that HAS an
---    `overrideSpellID` stored its override under an id we never look up.
---  * **up** — the aura-driven trackers pass `includeLinked`, so a cell can be
---    keyed by a LINKED aura id, from which the base spell's override is invisible.
---    `GetIdentityOwner` is the only route back up; without it an icon override on
---    a tracked buff silently did nothing (live, 2026-08-17).
---Resolution order is own key → base key → any sibling in the identity.  Multiple
---overrides inside one identity resolve in `pairs` order — pathological config, not
---worth ordering.
---
---Precedence, wherever this is used: a manual override outranks the CDM
---conditional-icon path AND suppresses the linked-spell icon swap — the same
---precedence the deleted CooldownViewer-child path applied.
---@param spellID number  the tracker's map key
---@return number|string|nil
---Return the override texture for a spellID, or nil if none configured.
---Reads `profile.icon_overrides` only.  File-scope so ResolveIconOverride can
---pass it by reference without allocating a closure per call.
---@param spellID number
---@return number|string|nil
local function getIconOverride(spellID)
    local overrides = private.profile and private.profile.icon_overrides
    if not overrides then return nil end
    return overrides[spellID]
end

private.Util.ResolveIconOverride = function(spellID)
    return resolveBySpellIdentity(spellID, getIconOverride)
end

---The id itself when `profile.icon_overrides` holds an entry under it.  The
---`getIconOverride` twin FindIconOverrideKey walks with, file-scope for the same
---no-closure reason.
---@param spellID number
---@return number|nil
local function iconOverrideKeyIfSet(spellID)
    local overrides = private.profile and private.profile.icon_overrides
    if overrides and overrides[spellID] ~= nil then return spellID end
    return nil
end

---The `icon_overrides` KEY that `ResolveIconOverride(spellID)` would read its
---texture from — own key, base key, or any identity sibling — or nil when none
---is set.  The same walk, returning the id instead of the texture, so a writer
---can clear or replace the entry a reader actually sees: an override saved under
---an `overrideSpellID` (the retired Icon Overrides picker's key) is invisible to a
---`icon_overrides[baseKey] = nil`.
---@param spellID number  a tracker key
---@return number|nil
private.Util.FindIconOverrideKey = function(spellID)
    return resolveBySpellIdentity(spellID, iconOverrideKeyIfSet)
end

---True when `spellID`, its base spell, or that entry's `overrideSpellID`
---appears in `list`.  The per-spell exclude lists (`pandemic_glow_excludes`)
---are written by the Options pickers under `overrideSpellID or spellID` and
---read back under whichever id the reader happens to hold, so a raw scan
---misses.  Linked ids are excluded — see ResolveByBaseOrOverride.
---@param spellID number
---@param list number[]|nil
---@return boolean
private.Util.BaseOrOverrideInList = function(spellID, list)
    if not list or #list == 0 then return false end
    return private.Util.ResolveByBaseOrOverride(spellID, listContainsId, list) == true
end

---Build an icon_visibility_mode-aware exclude filter for an Additional
---Frame's adopted icons.
---
---Its one caller is AdditionalFrameManager's collect pass, over the addon-owned
---icons TrinketTracker / ConsumableTracker / RacialTracker lend it.  The
---mode-off -> hide-instant -> fade decision tree below is the whole body; the
---routing short-circuit this used to carry is gone with the CooldownViewer
---children, since an AF *is* the routing target rather than a source.
---@param config { getSettingsFn: function, componentName: string, isReadyAddonFn: function? }
---  getSettingsFn   () -> settings table containing icon_visibility_mode and
---                  icon_visibility_faded_alpha.
---  componentName   component name passed to Anchor.GetEffectiveAlpha for the
---                  fade-target multiplier.
---  isReadyAddonFn  (icon, treatChargingAsOnCD) -> bool determining ready state.
---@return function excludeFilter  (icon: frame) -> bool
private.Util.MakeIconVisibilityFilter = function(config)
    local getSettingsFn = config.getSettingsFn
    local componentName = config.componentName
    local isReadyAddonFn = config.isReadyAddonFn
    return function(child)
        -- Gate against the component frame's actual IsShown() state — the
        -- only stable visibility signal during a mount cascade.  Anchoring's
        -- lastResult.rootVisible cache (read by IsAnchorChainVisible /
        -- GetEffectiveAlpha) flaps mid-mount because anchor.Refresh() updates
        -- r.rootVisible on every pass while only calling componentFrame:Hide()
        -- once at the first rulesVisible=false pass (the corresponding Show()
        -- at Anchoring.lua:1124 only fires in visibilityOnly mode).  The frame
        -- itself stays hidden for the entire mount, so checking IsShown() on
        -- the component frame avoids the flap entirely without timers or
        -- debounces.
        local componentFrame
        if componentName then
            local comp = private.ComponentManager.GetComponent(componentName)
            componentFrame = comp and comp.GetFrame and comp.GetFrame()
        end
        if componentFrame and not componentFrame:IsShown() then
            CancelIconFade(child)
            child:SetAlpha(0)
            return false
        end

        local settings = getSettingsFn()
        local mode = settings.icon_visibility_mode
        if (not mode or mode <= 1) or private.isEditMode then
            SetIconAlphaOverride(child, nil)
            restoreInnerTextures(child)
            return false
        end

        local treatCharging = settings.icon_visibility_treat_charging_as_on_cd
        if treatCharging == nil then treatCharging = true end

        local isReady = isReadyAddonFn and isReadyAddonFn(child, treatCharging)
        local shouldHide
        if mode == 2 or mode == 3 then
            shouldHide = isReady
        else
            shouldHide = not isReady
        end

        if not IsFadeMode(mode) then
            if shouldHide then
                SetIconAlphaOverride(child, 0)
                child:SetAlpha(0)
                zeroInnerTextures(child)
                return true
            end
            SetIconAlphaOverride(child, nil)
            restoreInnerTextures(child)
            return false
        end

        local fadedRatio = settings.icon_visibility_faded_alpha or 0.3
        local multiplier = shouldHide and fadedRatio or 1
        SetIconAlphaOverride(child, shouldHide and fadedRatio or nil)
        restoreInnerTextures(child)
        local effectiveAlpha = componentName and private.Anchor.GetEffectiveAlpha(componentName) or 1
        StartIconFade(child, multiplier * effectiveAlpha, 0.3)
        return false
    end
end

-- Single watcher for keybind cache invalidation — shared across all trackers.
-- Form/bonus-bar/page events are needed in addition to ACTIONBAR_SLOT_CHANGED
-- because druid shapeshift (and rogue stealth, priest shadowform, etc.) re-pages
-- the bonus bar; without invalidating slotKeyMap / spellKeyMap, the lazy maps
-- stay frozen at their first-built state and post-shift lookups miss.
--
-- After invalidating it fires OnKeybindsChanged, and the trackers redraw their
-- keybind text from that one signal.  Each used to run its own watcher that
-- invalidated the cache again and rebuilt it, so one burst paid a rebuild per
-- tracker plus a full refresh of every icon tracker.
--
-- ACTIONBAR_SLOT_CHANGED is filtered by what BuildKeybindMaps reads from a slot:
-- GetActionInfo's type and id, and GetMacroSpell for a macro.  In play it fires
-- ~4 times a second in combat, and 96% of those left the slot's action as it was
-- (counted live, 2026-09-21).  Compared as the event arrives, never in the
-- deferred tick, so several slots in one frame are each checked.  A slot not
-- seen before counts as changed; slot 0 (every slot) always invalidates and
-- forgets them all.
do
    local kbWatcher = CreateFrame("Frame")
    local kbPending = false
    local lastFormID = GetShapeshiftFormID()
    local slotActionType, slotActionID, slotMacroSpell = {}, {}, {}
    kbWatcher:RegisterEvent("UPDATE_BINDINGS")
    kbWatcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    kbWatcher:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    kbWatcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    kbWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    kbWatcher:SetScript("OnEvent", function(_, event, slot)
        if event == "UPDATE_SHAPESHIFT_FORM" then
            local formID = GetShapeshiftFormID()
            if formID == lastFormID then
                return
            end
            lastFormID = formID
        elseif event == "ACTIONBAR_SLOT_CHANGED" then
            if slot and slot ~= 0 then
                local actionType, actionID = GetActionInfo(slot)
                local macroSpell = actionType == "macro" and actionID and GetMacroSpell(actionID) or nil
                local seen = slotActionType[slot] ~= nil
                if seen and slotActionType[slot] == (actionType or false)
                    and slotActionID[slot] == actionID
                    and slotMacroSpell[slot] == macroSpell then
                    return
                end
                slotActionType[slot] = actionType or false
                slotActionID[slot] = actionID
                slotMacroSpell[slot] = macroSpell
            else
                wipe(slotActionType)
                wipe(slotActionID)
                wipe(slotMacroSpell)
            end
        end
        if not kbPending then
            kbPending = true
            C_Timer.After(0, function()
                kbPending = false
                wipe(keybindCache)
                slotKeyMap = nil
                spellKeyMap = nil
                private.Callback.Trigger("OnKeybindsChanged")
            end)
        end
    end)
end

---Mirror a CDM-backed tracker's frame onto its external anchor proxy,
---`CUE_<viewerKey>Anchor` -- the same global names the pre-12.1 containers
---published, so an external setup anchored to one keeps working.  No-op for a
---component with no viewer key.
---@param container frame  the component frame (plain rect, addon-owned)
---@param componentName string
private.Util.SyncAnchorProxy = function(container, componentName)
    local viewerKey = private.Util.GetComponentViewerKey(componentName)
    if not container or not viewerKey then return end
    syncAnchorProxy(container, "CUE_" .. viewerKey .. "Anchor")
end

-- ── 12.1 aura lockdown guards ───────────────────────────────────────────────

---True while instance-ID aura reads (GetAuraDataByAuraInstanceID /
---GetAuraDuration / AuraUtil.ForEachAura) would Lua-error from addon code:
---12.1+ while auras are secret (combat/encounters/M+/PvP).
---C_Secrets.ShouldAurasBeSecret is argument-free, returns a plain bool and is
---callable from tainted code. See patterns-secrets.md "12.1 Aura Lockdown".
private.Util.IsAuraAccessBlocked = function()
    return C_Secrets.ShouldAurasBeSecret()
end

---C_UnitAuras.GetAuraDuration guarded for 12.1: returns nil while aura access
---is blocked or when the instance ID itself is secret-wrapped (a secret
---argument from tainted code errors independently — observed at
---secrecy-transition edges). Out of secrecy this is the direct call.
private.Util.GetAuraDurationSafe = function(unit, auraInstanceID)
    if private.Util.IsAuraAccessBlocked() or issecretvalue(auraInstanceID) then
        return nil
    end
    return C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
end

---True while cooldown OR aura queries generally produce secret values.
---**Strictly wider than `InCombatLockdown()`**: secrecy also covers encounters,
---M+ and PvP, and it can outlive lockdown by a few seconds at a dungeon-exit
---regen — which is the whole reason this exists. Both predicates are
---argument-free, return plain bools and are callable from tainted code
---(`SecretPredicateAPIDocumentation.lua`).
local function isSecrecyActive()
    return C_Secrets.ShouldCooldownsBeSecret() or C_Secrets.ShouldAurasBeSecret()
end

-- Secrecy-deferred work. An `OnLeaveCombat` handler fires on
-- PLAYER_REGEN_ENABLED, which is NOT the same edge as secrecy ending — leaving
-- a dungeon drops combat while cooldowns/auras stay secret — so work that
-- drives Blizzard's CDM refresh from addon context can still land inside the
-- secret window and cache secret fields under our taint. There is no "secrecy
-- ended" event, so the queue is re-checked on a 1s timer that runs only while
-- something is pending and stops the moment it drains.
local secrecyPending = {}
local secrecyTickerActive = false

local function flushSecrecyPending()
    if isSecrecyActive() then
        C_Timer.After(1, flushSecrecyPending)
        return
    end
    secrecyTickerActive = false
    local pending = secrecyPending
    secrecyPending = {}
    for key, fn in pairs(pending) do
        private.printdebug("Util: secrecy cleared — running deferred", key)
        fn()
    end
end

---Run `fn` now, or defer it until cooldown/aura secrecy ends. One pending fn
---per key (latest wins), so repeat calls while pending neither stack work nor
---spam the debug log. `fn` MUST re-validate its own preconditions when it
---finally runs — world state may have moved during the wait.
---@param key string  coalescing key, also used in debug logs
---@param fn function
private.Util.RunWhenSecrecyClears = function(key, fn)
    if not isSecrecyActive() then
        fn()
        return
    end
    if secrecyPending[key] == nil then
        private.printdebug("Util: secrecy active — deferring", key)
    end
    secrecyPending[key] = fn
    if not secrecyTickerActive then
        secrecyTickerActive = true
        C_Timer.After(1, flushSecrecyPending)
    end
end

---The icon order a CDM tracker draws on the current spec: this spec's own
---`priority_order_spec[specKey]` when it has one, else the all-specs
---`priority_order`; nil when neither is a table.  The spec key is the one the
---CDM model was built with (CDMDataSource.GetResolvedSpecKey), so the order and
---the category overlay always agree and a layout pass pays no spec lookup.  With
---no spec system there is no key, and only the all-specs list is read.
---@param settings table|nil  a CDM tracker's settings
---@return number[]|nil
private.Util.GetTrackerOrder = function(settings)
    if not settings then return nil end
    local specKey = private.CDMDataSource.GetResolvedSpecKey()
    local lists = specKey and settings.priority_order_spec
    local own = type(lists) == "table" and lists[specKey]
    if type(own) == "table" then return own end
    local order = settings.priority_order
    if type(order) == "table" then return order end
    return nil
end

---Reused rank map for BuildSpellOrderRank; the trackers rank on every layout
---pass, so this must not allocate (performance.md).
local orderRankScratch = {}

---Icon-order rank for one CDM tracker's spell map, {[key] = rank}, lower first.
---
---Two layers.  The tracker's stored order for this spec (GetTrackerOrder: its
---own list, else the all-specs one) is the arrangement the player made in
---the Tracking tab (reorder or drag) and always wins; every key it does not mention
---keeps Blizzard's CooldownViewer order (CDMDataSource.GetSpellOrderRanks)
---behind it, offset past the arranged block so an arranged icon can never be
---overtaken.  An empty list therefore reproduces Blizzard's order exactly.
---Keys neither source knows — custom spells — come back nil, which every
---comparator here treats as "sort last".
---
---The identity hop covers a key that is not its own base.  It used to be the
---common case -- the aura trackers' maps carried override and linked ids as
---sibling keys -- which is exactly the duplicate `getTrackedSpellMap` no longer
---produces.  What is left for it: an item-backed entry's linked ids, which have
---no base spell to collapse onto, and a hand-edited priority_order.  Such a key
---inherits its owner's rank and ties with it, so the two land adjacent.
---
---Returns a REUSED table — sort with it immediately, never hold it across
---another call.  Nil for anything that is not one of the four CDM trackers,
---which is what keeps Additional Frames on their own assigned_spells order.
---@param componentName string
---@param spellMap table<number, true>  the keys to rank
---@return table<number, number>|nil
private.Util.BuildSpellOrderRank = function(componentName, spellMap)
    local viewerKey = private.Util.CDM_COMPONENT_VIEWER_KEYS[componentName]
    if not viewerKey then return nil end
    -- Ranks come from this tracker's OWN category.  Each of the four CDM
    -- trackers maps to exactly one, which is what makes the lookup unambiguous;
    -- a global rank map let a spell with entries in two categories carry its
    -- cooldown-bar position into the buff bar (CDMDataSource, resolvedOrderBySpell).
    local cdmRanks = private.CDMDataSource.GetSpellOrderRanks(
        private.Enum.CooldownViewerCategoryIDs[viewerKey])
    -- After the ranks: that call builds the model whose spec key picks the list.
    local order = private.Util.GetTrackerOrder(private.profile.components[componentName])
    local n = order and #order or 0
    wipe(orderRankScratch)
    for i = 1, n do
        orderRankScratch[order[i]] = i
    end
    for key in pairs(spellMap) do
        if orderRankScratch[key] == nil then
            -- CDM ranks are keyed by BASE spellID, so a hit here means the key
            -- is its own base and no identity walk is needed — the common case.
            local rank = cdmRanks and cdmRanks[key]
            if rank then
                orderRankScratch[key] = n + rank
            else
                -- A miss is an override or linked id, which takes its owner's
                -- rank; a custom spell has no owner and stays unranked.
                --
                -- Pins were all written before this loop, so a pinned owner is
                -- always visible here.  An UNpinned owner may not have been
                -- reached yet, but the fallback computes exactly the rank it
                -- would get, so the answer is the same either way and does not
                -- depend on pairs() order.
                local owner = private.CDMDataSource.GetIdentityOwner(key)
                if owner then
                    local ownerRank = orderRankScratch[owner]
                    if not ownerRank and cdmRanks and cdmRanks[owner] then
                        ownerRank = n + cdmRanks[owner]
                    end
                    orderRankScratch[key] = ownerRank
                end
            end
        end
    end
    return orderRankScratch
end

---Ranks for compareByOrderRank.  Module-level like the comparator so a sort
---allocates no closure; table.sort is synchronous, so there is no interleaving.
---@type table<number, number>|nil
local sortOrderRanks = nil

---Icon-order comparator for a plain spellID array: rank first, spellID as the
---tie-break.  Unranked keys sort LAST and stay together — that is custom
---spells, which the CDM has never heard of.
local function compareByOrderRank(a, b)
    local ra = sortOrderRanks[a]
    local rb = sortOrderRanks[b]
    if ra ~= rb then
        if not ra then return false end
        if not rb then return true end
        return ra < rb
    end
    return a < b
end

---Sort an array of spellIDs into icon order, in place.
---@param list number[]
---@param rank table<number, number>|nil  from BuildSpellOrderRank; nil sorts by
---  plain spellID, which is what an Additional Frame instance gets
private.Util.SortByOrderRank = function(list, rank)
    if not rank then
        table.sort(list)
        return
    end
    sortOrderRanks = rank
    table.sort(list, compareByOrderRank)
end

---Apply an addon-owned icon's cooldown sweep only when it changed. Re-issuing
---SetCooldown / SetCooldownFromDurationObject restarts the engine countdown, so
---the shown seconds jump on every poll tick and every layout pass. The applied
---timing is cached on the icon (`cdStart`/`cdDuration`). A DurationObject is a
---fresh object per query, so its start time is what tells a new cooldown (a
---Healthstone's next charge, with no off-cooldown moment in between) from the one
---on screen; while its values are secret it cannot be compared, and is applied on
---entering that state only. Call with no timing to clear. Shared by
---TrinketTracker and ConsumableTracker.
---@param icon frame
---@param start number?
---@param duration number?
---@param durObj table?
private.Util.SetIconCooldown = function(icon, start, duration, durObj)
    if durObj then
        local startTime = not durObj:HasSecretValues() and durObj:GetStartTime() or nil
        if icon.cdDuration == "durationObject" and (startTime == nil or icon.cdStart == startTime) then
            return
        end
        icon.cdStart, icon.cdDuration = startTime, "durationObject"
        icon.Cooldown:SetCooldownFromDurationObject(durObj)
    elseif start then
        if icon.cdStart == start and icon.cdDuration == duration then return end
        icon.cdStart, icon.cdDuration = start, duration
        icon.Cooldown:SetCooldown(start, duration)
    else
        icon.cdStart, icon.cdDuration = nil, nil
        icon.Cooldown:Clear()
    end
end
