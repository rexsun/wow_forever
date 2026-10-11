
--[[
    RaidBuffTracker component.
    Displays status icons for class raid buffs — Arcane Intellect, Battle Shout,
    Power Word: Fortitude, Mark of the Wild, Blessing of the Bronze, and Skyfury.

    Two display modes:
    1. "Own buff" icon: SecureActionButton for the buff your class provides.
       Glows when party/raid members are missing it. Click to cast.
       Saturation is the INVERSE of mode 2 and that is intentional -- an action
       button reads bright as "cast it", desaturated as "nothing to do".
    2. "All buffs" row (optional): Shows all 6 raid buff icons on yourself.
       Desaturated + glow when missing; normal + duration when present.

    Group scan is throttled:
    - Out of combat in dungeon/raid: every ~10s via C_Timer.NewTicker.
    - In combat: on ENCOUNTER_START and INCOMING_RESURRECT_CHANGED (accepted).
    - Own buff expiry: scheduled via C_Timer.NewTimer from non-secret duration data.
    No OnUpdate polling.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field RaidBuffTracker raidbufftracker

---@class raidbufftracker : component

---@type raidbufftracker
---@diagnostic disable-next-line: missing-fields
local comp = {}

comp.name = "RaidBuffTracker"

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local GROUP_SCAN_INTERVAL = 10

---@class raid_buff_def
---@field key string
---@field spellId number primary spell ID (for player detection and icon)
---@field spellIds number[]? every ID that counts as this buff (ranks, group versions, per-class variants), ascending
---@field label string locale key
---@field providerClass string uppercase English class token
---@field fallbackIcon number|nil texture FileID fallback
---@field clients table<string, true>? the game clients (ClientScope.CLIENT) that have this buff; nil = every one

-- A classic-content client casts these as ranks, and the group version is a
-- separate spell again, so the id the player actually carries is rarely the
-- retail one.  `spellIds` lists every id that counts as the buff, ascending,
-- with the retail id among them -- one table stays correct on both clients and
-- an id the running client does not have is simply never found.
--
-- The 1.x ids are not guesses: SkillLine -> SkillLineAbility -> SpellName over
-- the class skill lines of that client's own DB2 (build 1.60.1.69913,
-- 2026-09-18), and each one verified in SpellEffect as Effect 6 (APPLY_AURA)
-- with no trigger spell, so the cast id is also the aura id the scan looks for.
-- Recipe in `.context/memory/reference_spell_data_lookup.md`.
--
-- Paladin, Hunter, Rogue and Warlock have no row there: their group buffs are
-- blessings, auras, totem-likes and pet buffs, none of which is one cast that
-- covers the raid.  The same holds on Era, TBC and Wrath, where a Greater
-- Blessing covers one class.  Their new ranks come from the same skill-line
-- walk over each client's DB2 (1.15.9.70003, 2.5.6.69795, 3.80.2.70177); Era's
-- are Forever's.
--
-- MoP Classic (DB2 5.5.4.70032): Arcane Brilliance is 1459 there and Battle
-- Shout, Fortitude and Mark of the Wild keep their retail ids, so those rows
-- hold as they are.  A row with `clients` exists only there; a class's first
-- row is its own buff, the rest show under "show all".  Passive auras (Trueshot,
-- Unholy, Moonkin, Leader of the Pack, the shaman totems' successors) and pet
-- buffs are no one's cast, so they have no row.
---@type raid_buff_def[]
local RAID_BUFFS = {
    {
        key = "arcane_intellect",
        spellId = 1459,
        -- ranks 1-7 and Arcane Brilliance 1-3 (1459 is Arcane Brilliance on
        -- MoP), then Dalaran Intellect and Brilliance (Wrath, MoP)
        spellIds = { 1459, 1460, 1461, 10156, 10157, 23028, 27126, 27127, 42995, 43002, 61024, 61316 },
        label = "RAID_BUFF_ARCANE_INTELLECT",
        providerClass = "MAGE",
        fallbackIcon = 135932,
    },
    {
        key = "battle_shout",
        spellId = 6673,
        -- ranks 1-9 (6673 is rank 2 and also the retail id)
        spellIds = { 2048, 5242, 6192, 6673, 11549, 11550, 11551, 25289, 47436 },
        label = "RAID_BUFF_BATTLE_SHOUT",
        providerClass = "WARRIOR",
        fallbackIcon = 132333,
    },
    {
        key = "power_word_fortitude",
        spellId = 21562,
        -- ranks 1-8 and Prayer of Fortitude 1-4 (21562 is Prayer rank 1 on a
        -- classic client and Power Word: Fortitude itself on retail)
        spellIds = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564, 25389, 25392, 48161, 48162 },
        label = "RAID_BUFF_FORTITUDE",
        providerClass = "PRIEST",
        fallbackIcon = 135987,
    },
    {
        key = "mark_of_the_wild",
        spellId = 1126,
        -- ranks 1-9 and Gift of the Wild 1-4
        spellIds = { 1126, 5232, 5234, 6756, 8907, 9884, 9885, 21849, 21850, 26990, 26991, 48469, 48470 },
        label = "RAID_BUFF_MARK_OF_THE_WILD",
        providerClass = "DRUID",
        fallbackIcon = 136078,
    },
    {
        key = "blessing_of_the_bronze",
        spellId = 381748,
        spellIds = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 },
        label = "RAID_BUFF_BLESSING_OF_THE_BRONZE",
        providerClass = "EVOKER",
        fallbackIcon = 4630450,
        clients = { retail = true },
    },
    {
        key = "skyfury",
        spellId = 462854,
        label = "RAID_BUFF_SKYFURY",
        providerClass = "SHAMAN",
        fallbackIcon = 135791,
        clients = { retail = true },
    },
    {
        key = "commanding_shout",
        spellId = 469,
        spellIds = { 469, 47439, 47440 }, -- ranks 1-3 (TBC, Wrath); MoP's is 469
        label = "RAID_BUFF_COMMANDING_SHOUT",
        providerClass = "WARRIOR",
        clients = { tbc = true, wrath = true, mists = true },
    },
    { key = "blessing_of_kings", spellId = 20217, label = "RAID_BUFF_BLESSING_OF_KINGS", providerClass = "PALADIN", clients = { mists = true } },
    { key = "blessing_of_might", spellId = 19740, label = "RAID_BUFF_BLESSING_OF_MIGHT", providerClass = "PALADIN", clients = { mists = true } },
    {
        key = "legacy_of_the_emperor",
        -- 115921 is the cast, a dummy effect; the buff is one of two auras with
        -- the same effect and text (117666, 117667), and either counts.
        spellId = 115921,
        spellIds = { 117666, 117667 },
        label = "RAID_BUFF_LEGACY_OF_THE_EMPEROR",
        providerClass = "MONK",
        clients = { mists = true },
    },
    { key = "legacy_of_the_white_tiger", spellId = 116781, label = "RAID_BUFF_LEGACY_OF_THE_WHITE_TIGER", providerClass = "MONK", clients = { mists = true } },
    { key = "dark_intent", spellId = 109773, label = "RAID_BUFF_DARK_INTENT", providerClass = "WARLOCK", clients = { mists = true } },
    {
        key = "horn_of_winter",
        spellId = 57330,
        spellIds = { 57330, 57623 }, -- ranks 1-2 (Wrath); MoP's is 57330
        label = "RAID_BUFF_HORN_OF_WINTER",
        providerClass = "DEATHKNIGHT",
        clients = { wrath = true, mists = true },
    },
}
-- Drop the rows the running client does not have.
for i = #RAID_BUFFS, 1, -1 do
    local clients = RAID_BUFFS[i].clients
    if clients and not clients[private.ClientScope.CLIENT] then table.remove(RAID_BUFFS, i) end
end

---Buff order for display.
local BUFF_ORDER = {}
---Lookup by key.
local BUFF_BY_KEY = {}
for i, def in ipairs(RAID_BUFFS) do
    BUFF_ORDER[i] = def.key
    BUFF_BY_KEY[def.key] = def
end

---The buff definition this player's class can cast, or nil.
local ownBuffDef ---@type raid_buff_def?
do
    local _, classToken = UnitClass("player")
    for _, def in ipairs(RAID_BUFFS) do
        if def.providerClass == classToken then
            ownBuffDef = def
            break
        end
    end
end

---Resolve spell textures (may return nil at load; refreshed later).
local spellTextures = {} ---@type table<string, number?>
for _, def in ipairs(RAID_BUFFS) do
    spellTextures[def.key] = C_Spell.GetSpellTexture(def.spellId) or def.fallbackIcon
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local container ---@type Frame?
---The size applyLayout last gave `container` (Initialize's until then).
---GetComponentSize reports this rather than reading the frame back: the
---layout pass places a follower of this component right after re-anchoring
---it, when the frame's own size reads back stale.
local layoutW, layoutH = 200, 50
local eventFrame ---@type Frame?
local orderedIcons = {} ---@type table<number, Button>
local iconPool = {} ---@type table<number, Button>
local iconPoolSize = 0
local poolUsedCount = 0

---Per-icon state (keyed by icon frame ref — taint prevention).
local iconIsActive = {} ---@type table<Button, boolean>
local iconIsOwnBuff = {} ---@type table<Button, boolean>
local iconBuffDef = {} ---@type table<Button, table>
---The show/hide half of an icon's alpha, as hide_when_applied decided it.
---Alpha writers multiply this instead of reading GetAlpha() back, which
---would latch a transient 0 for good.
local iconShown = {} ---@type table<Button, boolean>

---Queued secure attribute updates for after combat.
local pendingAttributes = {} ---@type table<Button, {type: string, spell: string}>

---True from the pull until combat ends. A secure button cannot move in combat,
---so at the pull every icon takes the slot it would have with all of them
---shown; hide_when_applied then only fades, and a buff that becomes needed
---appears in its own slot instead of on top of the first icon.
local pinnedLayout = false

---Group scan state.
local groupMissingOwnBuff = false
local groupScanTicker ---@type table?
local unitsAwaitingRes = {} ---@type table<string, boolean> units with a pending resurrection
local ownBuffExpiryTimer ---@type table? scheduled callback for own buff expiry
local hadOwnBuff = false ---@type boolean whether the player had their own buff on last check

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getSettings()
    return private.profile.components[comp.name]
end

local function getEnabled()
    return getSettings().enabled
end

---Check if a specific buff key is enabled in tracked_buffs.
---@param buffKey string
---@return boolean
local function isBuffEnabled(buffKey)
    local val = getSettings().tracked_buffs[buffKey]
    if val == nil then return true end
    return val
end

---------------------------------------------------------------------------
-- Icon creation
---------------------------------------------------------------------------

---@param parent Frame
---@return Button
local function createIcon(parent) -- luacheck: ignore 212
    local icon = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    icon:SetSize(40, 40)
    icon:Hide()

    icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
    icon.Icon:SetAllPoints()
    icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(false)
    cd:SetCountdownAbbrevThreshold(600)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetSwipeColor(0, 0, 0, 0.5)
    cd:SetReverse(true)
    icon.Cooldown = cd

    icon.DurationText = cd:GetRegions()
    if icon.DurationText then
        -- Reparent above cooldown swipe so text isn't hidden behind it
        local textOverlay = CreateFrame("Frame", nil, icon)
        textOverlay:SetAllPoints(cd)
        textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)
        icon.DurationText:SetParent(textOverlay)
    end

    icon:RegisterForClicks("AnyDown", "AnyUp")

    -- Install CUE tooltip on this addon-owned icon. Resolver reads icon.spellID
    -- which is assigned by setSecureSpellAttributes when the icon is bound.
    -- isSecureClick=true so the EnableMouse formula honours settings.clickable.
    if private.Tooltip then
        private.Tooltip.Apply(icon, getSettings, function(self)
            if not self.spellID then return nil, nil end
            return "spell", self.spellID
        end, { kind = "own", isSecureClick = true })
    end

    return icon
end

---Get or create an icon from the pool.
---@return Button
local function acquireIcon()
    poolUsedCount = poolUsedCount + 1
    if poolUsedCount <= iconPoolSize then
        return iconPool[poolUsedCount]
    end
    iconPoolSize = iconPoolSize + 1
    local icon = createIcon(container)
    iconPool[iconPoolSize] = icon
    return icon
end

---------------------------------------------------------------------------
-- Secure attribute management
---------------------------------------------------------------------------

local function applyOrDeferAttributes(icon, attrs)
    if InCombatLockdown() then
        pendingAttributes[icon] = attrs
    else
        icon:SetAttribute("type", attrs.type)
        icon:SetAttribute("spell", attrs.spell)
        icon:SetAttribute("unit", attrs.unit)
    end
end

---Set click-to-cast spell on an icon.
---@param icon Button
---@param spellName string?
---@param spellID number?
local function setSecureSpellAttributes(icon, spellName, spellID)
    -- icon.spellID is the source of truth for the tooltip resolver — store it
    -- regardless of clickable so the tooltip works in non-clickable mode too.
    icon.spellID = spellID
    if not getSettings().clickable then
        if not InCombatLockdown() then
            icon:SetAttribute("type", nil)
            icon:SetAttribute("spell", nil)
            icon:SetAttribute("unit", nil)
        end
        return
    end
    if not spellName then
        applyOrDeferAttributes(icon, { type = nil, spell = nil, unit = nil })
        return
    end
    applyOrDeferAttributes(icon, { type = "spell", spell = spellName, unit = "player" })
end

local function flushPendingAttributes()
    if InCombatLockdown() then return end
    for icon, attrs in pairs(pendingAttributes) do
        icon:SetAttribute("type", attrs.type)
        icon:SetAttribute("spell", attrs.spell)
        icon:SetAttribute("unit", attrs.unit)
    end
    wipe(pendingAttributes)
end

---------------------------------------------------------------------------
-- Aura detection
---------------------------------------------------------------------------

---Check if the player has a given raid buff (handles multi-ID buffs like Blessing of the Bronze).
---@param def raid_buff_def
---@return table? auraData
local function getPlayerAuraForBuff(def)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(def.spellId)
    if aura then return aura end
    if def.spellIds then
        for _, id in ipairs(def.spellIds) do
            aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
            if aura then return aura end
        end
    end
    return nil
end

---Check if a unit has any of the given spell IDs as a buff.
---Uses C_UnitAuras.GetUnitAuraBySpellID (never AuraUtil.FindAuraByName).
---@param unit string
---@param spellIds number[]
---@return boolean
local function unitHasAnySpellId(unit, spellIds)
    for _, id in ipairs(spellIds) do
        if C_UnitAuras.GetUnitAuraBySpellID(unit, id) then
            return true
        end
    end
    return false
end

---Build the list of spell IDs to check for a buff definition.
---@param def raid_buff_def
---@return number[]
local function getCheckSpellIds(def)
    if def.spellIds then return def.spellIds end
    return { def.spellId }
end

---The ID of this buff the player can actually cast: the highest known one.
---`spellIds` is ascending, and a higher ID is always the better cast — a later
---rank, or the group version over the single-target one.  Falls back to
---`spellId` when none is known (retail's Blessing of the Bronze variants are
---aura IDs, not castable spells).
---@param def raid_buff_def
---@return number
local function resolveCastSpellId(def)
    local ids = getCheckSpellIds(def)
    for i = #ids, 1, -1 do
        if C_SpellBook.IsSpellInSpellBook(ids[i], Enum.SpellBookSpellBank.Player, true) then
            return ids[i]
        end
    end
    return def.spellId
end

---------------------------------------------------------------------------
-- Group missing-buff scan
---------------------------------------------------------------------------

---Forward declarations for functions used across definition order.
local updateGlows
local updateHideWhenAppliedAlpha

---Scan group/raid for members missing the player's own raid buff.
---@return boolean anyMissing true if at least one living member is missing the buff
local function scanGroupForMissingBuff()
    if not ownBuffDef then return false end

    local checkIds = getCheckSpellIds(ownBuffDef)
    local inRaid = IsInRaid()
    local numGroup
    local prefix

    if inRaid then
        numGroup = GetNumGroupMembers()
        prefix = "raid"
    elseif IsInGroup() then
        numGroup = GetNumSubgroupMembers()
        prefix = "party"
    else
        return false
    end

    for i = 1, numGroup do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit)
            and not (UnitInPartyIsAI and UnitInPartyIsAI(unit)) then
            if not unitHasAnySpellId(unit, checkIds) then
                return true
            end
        end
    end

    -- In party (not raid), player is not included in party1..N
    if not inRaid then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(ownBuffDef.spellId)
        if not aura then
            return true
        end
    end

    return false
end

---Run the group scan and update state.
local function doGroupScan()
    groupMissingOwnBuff = scanGroupForMissingBuff()
    if ownBuffDef then
        hadOwnBuff = getPlayerAuraForBuff(ownBuffDef) ~= nil
    end
    updateGlows()
    updateHideWhenAppliedAlpha()
end

---Start the out-of-combat group scan ticker.
local function startGroupScanTicker()
    if groupScanTicker then return end
    -- Events stay registered while disabled, so every restart path lands here.
    if not getEnabled() then return end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return end
    if InCombatLockdown() then return end

    doGroupScan()
    groupScanTicker = C_Timer.NewTicker(GROUP_SCAN_INTERVAL, doGroupScan)
end

---Stop the group scan ticker.
local function stopGroupScanTicker()
    if groupScanTicker then
        groupScanTicker:Cancel()
        groupScanTicker = nil
    end
end

---------------------------------------------------------------------------
-- Refresh logic
---------------------------------------------------------------------------

---Resolve texture for a buff definition, caching result.
---@param def raid_buff_def
---@return number
local function getBuffTexture(def)
    local texture = spellTextures[def.key]
    if not texture then
        texture = C_Spell.GetSpellTexture(def.spellId) or def.fallbackIcon
        spellTextures[def.key] = texture
    end
    return texture
end

---Add the own-buff icon (the buff this class provides).
---@param settings table
---@param iconIndex number
---@return number iconIndex updated index
local function addOwnBuffIcon(settings, iconIndex)
    if not ownBuffDef then return iconIndex end
    if not isBuffEnabled(ownBuffDef.key) then return iconIndex end

    local aura = getPlayerAuraForBuff(ownBuffDef)
    local isActive = aura ~= nil
    local allBuffed = isActive and not groupMissingOwnBuff

    iconIndex = iconIndex + 1
    local icon = acquireIcon()
    orderedIcons[iconIndex] = icon

    iconIsOwnBuff[icon] = true
    iconIsActive[icon] = isActive
    iconBuffDef[icon] = ownBuffDef
    icon.Icon:SetTexture(getBuffTexture(ownBuffDef))

    -- Saturation is deliberately INVERTED against addAllBuffIcons: this icon is a
    -- click-to-cast button, not a status readout.  Bright means "cast it", grey
    -- means "nothing to do" -- the same intent hide_when_applied takes further by
    -- fading to alpha 0 once allBuffed.
    if isActive then
        icon.Icon:SetDesaturated(true)
        local durObj = private.Util.GetAuraDurationSafe("player", aura.auraInstanceID)
        if durObj and settings.show_duration then
            icon.Cooldown:SetCooldownFromDurationObject(durObj)
        else
            icon.Cooldown:Clear()
        end
    else
        icon.Icon:SetDesaturated(false)
        icon.Cooldown:Clear()
    end
    icon.Cooldown:SetHideCountdownNumbers(settings.hide_cd_text == true)
    icon.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)

    -- Click-to-cast: set spell attribute
    local castId = resolveCastSpellId(ownBuffDef)
    setSecureSpellAttributes(icon, C_Spell.GetSpellName(castId), castId)

    if not InCombatLockdown() then
        icon:Show()
    end
    -- hide_when_applied: alpha 0 when all group members have the buff
    iconShown[icon] = not (allBuffed and settings.hide_when_applied)
    icon:SetAlpha(iconShown[icon] and 1 or 0)
    return iconIndex
end

---Add icons for all 6 raid buffs (optional display).
---@param settings table
---@param iconIndex number
---@return number iconIndex updated index
local function addAllBuffIcons(settings, iconIndex)
    if not settings.show_all_buffs then return iconIndex end

    for _, buffKey in ipairs(BUFF_ORDER) do
        local def = BUFF_BY_KEY[buffKey]
        if not isBuffEnabled(buffKey) then
            -- skip disabled buffs
        elseif ownBuffDef and def.key == ownBuffDef.key then
            -- skip own buff in "all" row (already shown above)
        else
            local aura = getPlayerAuraForBuff(def)
            local isActive = aura ~= nil

            iconIndex = iconIndex + 1
            local icon = acquireIcon()
            orderedIcons[iconIndex] = icon

            iconIsOwnBuff[icon] = false
            iconIsActive[icon] = isActive
            iconBuffDef[icon] = def
            icon.Icon:SetTexture(getBuffTexture(def))

            if isActive then
                icon.Icon:SetDesaturated(false)
                local durObj = private.Util.GetAuraDurationSafe("player", aura.auraInstanceID)
                if durObj and settings.show_duration then
                    icon.Cooldown:SetCooldownFromDurationObject(durObj)
                else
                    icon.Cooldown:Clear()
                end
            else
                icon.Icon:SetDesaturated(true)
                icon.Cooldown:Clear()
            end
            icon.Cooldown:SetHideCountdownNumbers(settings.hide_cd_text == true)
            icon.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)

            -- No click-to-cast for other classes' buffs — but still bind the
            -- spellID so the tooltip resolver can render the buff.
            setSecureSpellAttributes(icon, nil, def.spellId)

            if not InCombatLockdown() then
                icon:Show()
            end
            -- hide_when_applied: alpha 0 when buff is active
            iconShown[icon] = not (isActive and settings.hide_when_applied)
            icon:SetAlpha(iconShown[icon] and 1 or 0)
        end
    end

    return iconIndex
end

---Combat-safe: toggle icon alpha based on current aura state.
---SetAlpha is not protected, so this is safe to call during combat.
updateHideWhenAppliedAlpha = function()
    local settings = getSettings()
    if not settings.hide_when_applied then return end

    local alpha = container and container:GetAlpha() or 1
    for _, icon in ipairs(orderedIcons) do
        local def = iconBuffDef[icon]
        if def then
            local aura = getPlayerAuraForBuff(def)
            local isActive = aura ~= nil
            local shouldHide
            if iconIsOwnBuff[icon] then
                shouldHide = isActive and not groupMissingOwnBuff
            else
                shouldHide = isActive
            end
            iconShown[icon] = not shouldHide
            icon:SetAlpha(shouldHide and 0 or alpha)
        end
    end
end

---Build the ordered list of icons based on current buff state.
local function refreshAllIcons()
    -- Stop glows and return all current icons to pool
    local inCombat = InCombatLockdown()
    for _, icon in ipairs(orderedIcons) do
        private.GlowEffect.StopAll(icon)
        if inCombat then
            icon:SetAlpha(0)
        else
            icon:Hide()
        end
    end
    wipe(orderedIcons)
    poolUsedCount = 0

    local settings = getSettings()
    local iconIndex = 0

    iconIndex = addOwnBuffIcon(settings, iconIndex)
    iconIndex = addAllBuffIcons(settings, iconIndex)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function applyLayout()
    if not container then return end
    if InCombatLockdown() then return end

    local settings = getSettings()
    local iconSize = settings.icon_size
    local iconHeight = (settings.icon_height and settings.icon_height > 0) and settings.icon_height or iconSize
    local offset = settings.icon_offset
    local layout = settings.layout
    -- Pinned (combat): every icon keeps a slot; hide_when_applied only fades.
    local collapseApplied = settings.hide_when_applied and not pinnedLayout

    -- Count only layout-visible icons (skip those hidden by hide_when_applied)
    local count = 0
    for _, icon in ipairs(orderedIcons) do
        local shouldHide = false
        if collapseApplied and iconIsActive[icon] then
            if iconIsOwnBuff[icon] then
                shouldHide = not groupMissingOwnBuff
            else
                shouldHide = true
            end
        end
        if not shouldHide then
            count = count + 1
        end
    end

    if count == 0 then
        layoutW, layoutH = 1, 1
        container:SetSize(1, 1)
        private.Util.ApplyComponentBackground(container, settings.background)
        return
    end

    local totalW, totalH

    if layout == "vertical" then
        totalW = iconSize
        totalH = count * iconHeight + (count - 1) * offset
    elseif layout == "block" then
        local cols = math.ceil(count / 2)
        local rows = math.min(count, 2)
        totalW = cols * iconSize + (cols - 1) * offset
        totalH = rows * iconHeight + (rows - 1) * offset
    else -- horizontal
        totalW = count * iconSize + (count - 1) * offset
        totalH = iconHeight
    end

    layoutW, layoutH = totalW, totalH
    container:SetSize(totalW, totalH)

    local visibleIdx = 0
    for _, icon in ipairs(orderedIcons) do
        icon:SetSize(iconSize, iconHeight)
        icon:ClearAllPoints()

        local shouldHide = false
        if collapseApplied and iconIsActive[icon] then
            if iconIsOwnBuff[icon] then
                shouldHide = not groupMissingOwnBuff
            else
                shouldHide = true
            end
        end

        if shouldHide then
            private.Pixel.SetPoint(icon, "TOPLEFT", container, "TOPLEFT", 0, 0)
        else
            local idx = visibleIdx
            visibleIdx = visibleIdx + 1
            if layout == "vertical" then
                private.Pixel.SetPoint(icon, "TOPLEFT", container, "TOPLEFT", 0, -(idx * (iconHeight + offset)))
            elseif layout == "block" then
                local col = math.floor(idx / 2)
                local row = idx % 2
                private.Pixel.SetPoint(icon, "TOPLEFT", container, "TOPLEFT",
                    col * (iconSize + offset), -(row * (iconHeight + offset)))
            else -- horizontal
                private.Pixel.SetPoint(icon, "TOPLEFT", container, "TOPLEFT", idx * (iconSize + offset), 0)
            end
        end

        private.Util.ApplyIconBorder(icon)
        private.Util.ApplyIconVisibility(icon, settings.hide_icon)
    end

    private.Util.ApplyComponentBackground(container, settings.background)
end

---------------------------------------------------------------------------
-- Glow management
---------------------------------------------------------------------------

updateGlows = function()
    local settings = getSettings()
    local glowSettings = settings.glow
    if not glowSettings or not glowSettings.enabled then return end

    -- Only glow in dungeon and raid instances
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        for _, icon in ipairs(orderedIcons) do
            private.GlowEffect.StopAll(icon)
        end
        return
    end

    for _, icon in ipairs(orderedIcons) do
        local isOwn = iconIsOwnBuff[icon]
        local isActive = iconIsActive[icon]

        if isOwn then
            -- Own buff: glow when group members are missing it
            if groupMissingOwnBuff and glowSettings.missing_enabled then
                private.GlowEffect.StartPulse(icon)
            else
                private.GlowEffect.StopPulse(icon)
            end
        else
            -- All-buff row: glow when missing on self
            if not isActive then
                if glowSettings.missing_enabled then
                    private.GlowEffect.StartPulse(icon)
                end
            else
                private.GlowEffect.StopPulse(icon)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Own-buff expiry scheduling
---------------------------------------------------------------------------

---Cancel any pending expiry timer.
local function cancelOwnBuffExpiryTimer()
    if ownBuffExpiryTimer then
        ownBuffExpiryTimer:Cancel()
        ownBuffExpiryTimer = nil
    end
end

---Schedule a callback for when the player's own buff expires.
---Computes the exact remaining time when the duration data is readable.
local function scheduleOwnBuffExpiry()
    cancelOwnBuffExpiryTimer()
    if not ownBuffDef or not getEnabled() then return end

    local aura = getPlayerAuraForBuff(ownBuffDef)
    if not aura then return end

    -- Plain today only because every tracked buff carries the "aura never
    -- secret" flag. Fail closed if one ever loses it: no timer, and the
    -- UNIT_AURA path still catches the expiry.
    local expirationTime = aura.expirationTime
    local duration = aura.duration
    if issecretvalue(expirationTime) or issecretvalue(duration) then return end
    if not expirationTime or not duration or duration == 0 then return end

    local remaining = expirationTime - GetTime()
    if remaining <= 0 then return end

    ownBuffExpiryTimer = C_Timer.NewTimer(remaining + 0.1, function()
        ownBuffExpiryTimer = nil
        -- Own buff just expired — group is now missing it
        groupMissingOwnBuff = true
        updateGlows()
        updateHideWhenAppliedAlpha()
    end)
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------

local function onEvent(self, event, ...)
    if event == "UNIT_AURA" then
        -- Player-only (registered via RegisterUnitEvent)
        if InCombatLockdown() then
            -- In combat: detect own buff transitions (absent→present / present→absent)
            if ownBuffDef then
                local hasOwn = getPlayerAuraForBuff(ownBuffDef) ~= nil
                if not hasOwn then
                    groupMissingOwnBuff = true
                    hadOwnBuff = false
                    cancelOwnBuffExpiryTimer()
                elseif not hadOwnBuff then
                    -- Buff just applied (absent→present) — raid-wide, assume all got it
                    groupMissingOwnBuff = false
                    hadOwnBuff = true
                    scheduleOwnBuffExpiry()
                else
                    -- Buff already present (refresh/recast). If group was
                    -- flagged missing, the recast likely covered them —
                    -- schedule a delayed rescan to confirm.
                    if groupMissingOwnBuff then
                        C_Timer.After(1.5, function()
                            groupMissingOwnBuff = scanGroupForMissingBuff()
                            updateGlows()
                            updateHideWhenAppliedAlpha()
                        end)
                    end
                end
            end
            -- Refresh iconIsActive for existing icons (combat-safe table writes)
            for _, icon in ipairs(orderedIcons) do
                local def = iconBuffDef[icon]
                if def then
                    iconIsActive[icon] = getPlayerAuraForBuff(def) ~= nil
                end
            end
            updateGlows()
            updateHideWhenAppliedAlpha()
        else
            local wasHadOwnBuff = hadOwnBuff
            doGroupScan()
            comp.Refresh()
            -- When own buff was just applied, raid members may not have it yet.
            -- Schedule a short-delay rescan so we don't wait for the 10s ticker.
            if ownBuffDef and hadOwnBuff and (not wasHadOwnBuff or groupMissingOwnBuff) then
                C_Timer.After(1.5, function()
                    if not InCombatLockdown() then
                        doGroupScan()
                        comp.Refresh()
                    end
                end)
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        doGroupScan()
        comp.Refresh()
    elseif event == "ENCOUNTER_START" then
        doGroupScan()
    elseif event == "INCOMING_RESURRECT_CHANGED" then
        local unit = ...
        if not unit then return end
        if UnitHasIncomingResurrection(unit) then
            -- Res cast started — track this unit
            unitsAwaitingRes[unit] = true
        elseif unitsAwaitingRes[unit] then
            -- Pending res cleared — accepted or declined
            unitsAwaitingRes[unit] = nil
            if not UnitIsDeadOrGhost(unit) then
                -- Unit is alive — they accepted. Assume buff is missing.
                groupMissingOwnBuff = true
                updateGlows()
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Also cleared by OnLeaveCombat; both run on this event, in either order.
        pinnedLayout = false
        flushPendingAttributes()
        startGroupScanTicker()
        comp.Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        stopGroupScanTicker()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        comp.Refresh()
    end
end

---------------------------------------------------------------------------
-- Component interface
---------------------------------------------------------------------------

function comp.Initialize()
    container = CreateFrame("Frame", "CUE_RaidBuffTracker", UIParent)
    container:SetSize(200, 50)

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")

    private.Callback.Register("OnEnterCombat", function()
        -- PLAYER_REGEN_DISABLED, before the lockdown: the last chance to lay out.
        pinnedLayout = true
        comp.Refresh()
    end)

    private.Callback.Register("OnLeaveCombat", function()
        pinnedLayout = false
        comp.StopAllGlows()
        flushPendingAttributes()
        comp.Refresh()
    end)

    -- Start group scan ticker if already in instance
    startGroupScanTicker()

    comp.Refresh()
end

function comp.GetFrame()
    return container
end

function comp.StopAllGlows()
    for _, icon in ipairs(orderedIcons) do
        private.GlowEffect.StopAll(icon)
    end
    for i = 1, iconPoolSize do
        private.GlowEffect.StopAll(iconPool[i])
    end
end

---Lightweight alpha sync for position_reference inheritance.
---SetAlpha is not protected, so this is safe to call during combat.
function comp.SyncAlpha()
    if not container then return end
    local alpha = private.Anchor.GetEffectiveAlpha(comp.name)
    container:SetAlpha(alpha)
    -- When chain is hidden, alpha=0 (GetEffectiveAlpha returns 0 for
    -- rootVisible=false).  Secure containers stay Show()n so SyncAlpha
    -- can restore visibility during combat — check alpha, not IsShown.
    if alpha == 0 then
        for _, icon in ipairs(orderedIcons) do
            icon:SetAlpha(0)
            if icon.Cooldown then icon.Cooldown:Clear() end
        end
        return
    end
    for _, icon in ipairs(orderedIcons) do
        icon:SetAlpha(iconShown[icon] and alpha or 0)
    end
end

---A font edit this Refresh cannot apply -- in combat, or while hidden -- waits
---for the next one that draws the icons: the combat-exit pass runs without
---the font pass.
local fontsOwed = false

function comp.Refresh()
    if not container then return end
    if private.fontsDirty then fontsOwed = true end
    if InCombatLockdown() then return end

    local shouldShow = (getEnabled() or private.isEditMode) and private.Anchor.IsVisibleForComponent(comp.name)

    if shouldShow then
        local alpha = private.Anchor.GetEffectiveAlpha(comp.name)
        container:SetAlpha(alpha)
        container:Show()

        if fontsOwed then
            fontsOwed = false
            local settings = getSettings()
            for i = 1, iconPoolSize do
                local icon = iconPool[i]
                if icon.DurationText then
                    private.Util.ApplyFontProfile(icon.DurationText, settings.duration_font, icon)
                end
            end
        end

        refreshAllIcons()

        -- Sync icon alpha/strata with container (icons parented to UIParent).
        -- iconShown is the show/hide half refreshAllIcons decided
        -- (hide_when_applied); multiply by container alpha so fade/visibility
        -- rules still apply.
        local strata = container:GetFrameStrata()
        local level = container:GetFrameLevel()
        for _, icon in ipairs(orderedIcons) do
            icon:SetAlpha(iconShown[icon] and alpha or 0)
            icon:SetFrameStrata(strata)
            icon:SetFrameLevel(level + 1)
        end

    else
        container:Hide()
        -- Hide ALL pool icons (parented to UIParent, won't auto-hide with container).
        -- orderedIcons alone isn't sufficient: a previous layout pass may have left
        -- icons visible via SyncAlpha that aren't in the current orderedIcons list.
        for i = 1, iconPoolSize do
            iconPool[i]:Hide()
        end
    end

    applyLayout()
    updateGlows()
    scheduleOwnBuffExpiry()
end

comp.ContentLayout = function()
    refreshAllIcons()
    applyLayout()
end

function comp.OnEnable()
    if container and not InCombatLockdown() then
        container:Show()
        local alpha = private.Anchor.GetEffectiveAlpha(comp.name)
        container:SetAlpha(alpha)
        comp.Refresh()
        startGroupScanTicker()
    end
end

function comp.OnDisable()
    if container and not InCombatLockdown() then
        container:Hide()
        for i = 1, iconPoolSize do
            iconPool[i]:Hide()
        end
        stopGroupScanTicker()
        cancelOwnBuffExpiryTimer()
    end
end

function comp.GetComponentName()
    return comp.name
end

function comp.GetSettings()
    return getSettings()
end

function comp.GetEnabled()
    return getEnabled()
end

function comp.GetWantsContentWidth()
    return true
end

function comp.IsCollapsed()
    return #orderedIcons == 0
end

function comp.GetComponentSize()
    if not container then return 0, 0 end
    return layoutW, layoutH
end

---------------------------------------------------------------------------
-- Public accessors (for Options UI)
---------------------------------------------------------------------------

function comp.GetBuffDefinitions()
    return RAID_BUFFS
end

---Get the localized buff label for a buff key.
---@param key string
---@return string
function comp.GetBuffLabel(key)
    local def = BUFF_BY_KEY[key]
    if not def then return key end
    local L = private.L
    return L and L[def.label] or def.label
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

private.RaidBuffTracker = comp
private.ComponentManager.RegisterComponent("RaidBuffTracker", comp)
