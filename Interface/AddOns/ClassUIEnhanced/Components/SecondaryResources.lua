
---@type string, private
local _, private = ...

local LibSharedMedia = LibStub("LibSharedMedia-3.0")
local LAC = LibStub("LibAuraContainer-1.0")

---@param spellID number
---@return boolean
local function IsPlayerSpell(spellID)
    return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
end

-- This file used to carry a `getCdmViewerFrame` seam: every proc-detection
-- feature here read CooldownViewer children, and that wrapper disabled them all
-- in one place when the CDM was not delivering.  Every one of them has since
-- moved to an engine-driven aura tap — Divine Purpose and Lock and Load, then
-- Ignore Pain, the Sweeping Strikes / Teachings / Coup de Grâce stack strips,
-- and finally Essence Burst — so nothing in this file reads a viewer child any
-- more and the seam went with the last caller.

---@class private : table
---@field SecondaryResources secondaryresources

---@class secondaryresources : component
---@field CreateSecondaryResources fun() Creates the parent container frame for secondary resource bars

---@type secondaryresources
---@diagnostic disable-next-line: missing-fields
local secondaryResources = {}

secondaryResources.name = "SecondaryResources"

-- ── Constants ────────────────────────────────────────────────────────────────
-- All spell IDs, sentinel strings, max values, and lookup tables are packed into
-- a single table on the private namespace to stay within Lua 5.1's 200-local limit.
-- A short local alias `SRC` keeps call-site code concise.

---@class sr_constants : table
local SRC = {}
private._sr = SRC

-- Sentinel strings (used as playerPowerType values for custom-tracked resources)
SRC.SOUL_FRAG_VENGEANCE    = "SOUL_FRAG_VENG"
SRC.SOUL_FRAG_DEVOURER     = "SOUL_FRAG_DEV"
SRC.TOTS_CHARGES_SURVIVAL   = "TOTS_CHARGES_SURVIVAL"
SRC.ICICLES_FROST           = "ICICLES_FROST"
SRC.MW_CHARGES_ENHANCEMENT  = "MW_CHARGES_ENHANCEMENT"
SRC.WW_CHARGES_FURY         = "WW_CHARGES_FURY"
SRC.FIRE_BLAST_CHARGES      = "FIRE_BLAST_CHARGES"
SRC.STAGGER_BREWMASTER      = "STAGGER_BM"
SRC.VITALITY_MONK           = "VITALITY_MONK"
SRC.SKYRIDING_VIGOR         = "SKYRIDING_VIGOR"
SRC.IGNORE_PAIN_PROT        = "IGNORE_PAIN_PROT"
SRC.SWEEPING_STRIKES_ARMS   = "SWEEPING_STRIKES_ARMS"
SRC.TEACHINGS_MONK          = "TEACHINGS_MONK"
SRC.WILD_IMPS_DEMO          = "WILD_IMPS_DEMO"

-- Protection Warrior: Ignore Pain
SRC.IGNORE_PAIN_SPELL_ID    = 190456
SRC.IGNORE_PAIN_MAX_STACKS  = 100

-- Arms Warrior: Sweeping Strikes
-- Talent ID and buff aura ID happen to be the same in current builds, but
-- kept as separate constants in case Blizzard ever splits them.
-- Buff is stack-based: 12 charges base, 18 with Improved Sweeping Strikes (383155).
-- Each single-target damaging ability consumes a stack and triggers an extra hit.
SRC.SS_TALENT_ID            = 260708
SRC.SS_BUFF_SPELL_ID        = 260708
SRC.SS_IMPROVED_TALENT_ID   = 383155
SRC.SS_MAX_BASE             = 12
SRC.SS_MAX_IMPROVED         = 18

-- Mistweaver Monk: Teachings of the Monastery
-- Talent and stacking buff aura share spell ID 116645 (like Sweeping Strikes),
-- but kept as separate constants in case Blizzard ever splits them. The talent
-- gates the resolver; the buff aura (up to 4 stacks, 20s) is what the CDM viewer
-- scan matches and the user adds to Blizzard's tracked buffs.
SRC.TOTM_TALENT_ID          = 116645
SRC.TOTM_BUFF_SPELL_ID      = 116645
SRC.TOTM_MAX_STACKS         = 4

-- Demon Hunter Soul Fragments
SRC.VENG_SOUL_FRAG_SPELL = 228477   -- Spirit Bomb: GetSpellCastCount → fragment count
SRC.VENG_SOUL_FRAG_MAX   = 6
-- Devourer spell IDs — inlined at usage sites:
-- 1217605 = GetSpellCastCount → soul count 0-50, 1217607 = Void Metamorphosis buff, 1247534 = Soul Glutton talent

-- Demon Hunter: UNCOLLECTED Soul Fragments — the ones lying on the ground near
-- the player, not the collected pool the two primaries above show (Vengeance
-- reads 228477's cast count, Devourer 1217605's). The game tracks them with a
-- player buff literally named "Soul Fragments" whose stack count IS that number.
-- A second row alongside the spec's own primary, not a replacement. The count is
-- never read -- the aura is secret, so the strip is engine-rendered off a
-- player-bound AuraContainer, same as Wild Imps and Arcane Salvo.
--
-- BOTH ids go in ONE map. A character is one spec, so only one of them can ever
-- be up, and the per-spec cap below is what discriminates -- which means the
-- id → spec assignment never has to be right. That matters: 203981 is
-- "Consuming a nearby Soul Fragment heals you" (Havoc + Vengeance) and 1245577
-- is "...empowers you" (Devourer), and the Havoc half of that is inferred from
-- the tooltip wording, not stated by the game data.
--
-- The cap is selected from the SPEC INDEX, never from which aura is present:
-- both the stack count and the aura data are secret, so "which one is up" is not
-- a readable fact. See stackTap.nearbySoulsMax.
SRC.NEARBY_SOULS_DH = "NEARBY_SOULS_DH"
SRC.NEARBY_SOULS_AURA_ID = 203981 -- Havoc + Vengeance
SRC.NEARBY_SOULS_VOID_AURA_ID = 1245577 -- Devourer
SRC.NEARBY_SOULS_MAX = 20 -- Havoc + Vengeance
SRC.NEARBY_SOULS_MAX_DEVOURER = 15 -- Devourer

-- Survival Hunter: Tip of the Spear
SRC.TOTS_MAX_CHARGES = 3
SRC.TOTS_TALENT_ID   = 260285
SRC.TOTS_AURA_ID     = 260286

-- Guardian Druid: Ironfur
SRC.IRONFUR_GUARDIAN      = "IRONFUR_GUARDIAN"
SRC.IRONFUR_SPELL_ID      = 192081
SRC.IRONFUR_BASE_DURATION = 7.0   -- flat 7s, not affected by haste
SRC.MANGLE_SPELL_ID       = 33917
SRC.FR_SPELL_ID           = 22842  -- Frenzied Regeneration
SRC.URSOCS_ENDURANCE_ID   = 393611 -- passive talent: +2s Ironfur/Barkskin
SRC.GOE_TALENT_ID         = 155578 -- Guardian of Elune: Mangle → next IF +3s or FR +20% heal
SRC.URSOCS_BONUS          = 2.0
SRC.GOE_BONUS             = 3.0

-- Frost Mage: Icicles
SRC.ICICLES_MAX           = 5
SRC.ICICLES_AURA_ID       = 205473
SRC.ICICLES_BASE_DURATION = 6.0   -- base seconds per Icicle, modified by haste
SRC.HAILSTONES_TALENT_ID  = 1247742  -- reduces Icicle generation time by 1 sec
SRC.GLACIAL_SPIKE_SPELL   = 199786

-- Frost Mage: Shatter, driven by stacks of the Freezing debuff the player
-- applies to the CURRENT TARGET. A second row alongside Icicles, not a
-- replacement for it. The stack count is never read: the aura is secret, so the
-- strip is engine-rendered off a target-bound AuraContainer.
SRC.SHATTER_FREEZING      = "SHATTER_FREEZING"
SRC.FREEZING_AURA_ID      = 1221389
SRC.FREEZING_MAX_STACKS   = 20

-- Demonology Warlock: Wild Imps, driven by stacks of the player buff Blizzard
-- maintains for exactly this ("Displays the number of Wild Imps under your
-- command"). A second row alongside Soul Shards, not a replacement. The count is
-- never read -- the aura is secret, so the strip is engine-rendered off a
-- player-bound AuraContainer, same as Sweeping Strikes / Teachings.
-- The aura itself caps at 99 stacks (SpellAuraOptions.CumulativeAura), which is
-- not a renderable strip; 15 is the display cap, wide enough for a Hand of
-- Gul'dan triple stacked on top of an existing camp. Counts past it are not
-- lost -- the bound readout still shows the real number, and with segmentation
-- off the single fill just pins full.
SRC.WILD_IMP_AURA_ID      = 296553
SRC.WILD_IMP_MAX_STACKS   = 15

-- Arcane Mage: Arcane Salvo, driven by stacks of the player buff that banks the
-- missiles Arcane Barrage fires off. A second row alongside Arcane Charges, not
-- a replacement. The count is never read -- the aura is secret, so the strip is
-- engine-rendered off a player-bound AuraContainer, same as Wild Imps.
-- The cap is talent-scaled: 20 base, 25 with the Sunfury hero talent Spellfire
-- Salvo, resolved per render by stackTap.arcaneSalvoMax the way Sweeping
-- Strikes resolves its own 12/18 flip.
SRC.ARCANE_SALVO = "ARCANE_SALVO"
SRC.ARCANE_SALVO_AURA_ID = 1242974
SRC.ARCANE_SALVO_MAX_BASE = 20
SRC.ARCANE_SALVO_MAX_SPELLFIRE = 25
SRC.SPELLFIRE_SALVO_TALENT_ID = 1260616

-- Demon Hunter Aldrachi Reaver: Art of the Glaive, the counter banking consumed
-- Soul Fragments toward the Reaver's Glaive proc. ONE aura across all three
-- specs -- only the threshold differs, and the aura's own
-- SpellAuraOptions.CumulativeAura (80) is engine headroom, NOT the displayed
-- cap. The real numbers live only in the buff text: "At [ Havoc : 6 /
-- Vengeance, Devourer 20 ] Reaver's Glaive is available to cast."
--
-- The count is never read -- the aura is secret, so the strip is engine-rendered
-- off a player-bound AuraContainer, same as Wild Imps and Arcane Salvo.
--
-- On Havoc this is the PRIMARY: that spec has no other secondary resource
-- (specSecondaryPower.DEMONHUNTER[1] is false), so it takes row 1 rather than
-- needing the extras-only configuration the `count > 0` gate rules out. On
-- Vengeance and Devourer it is an extra row beside their existing primary. Each
-- spec carries its own enable setting.
SRC.ART_OF_GLAIVE = "ART_OF_GLAIVE"
SRC.AOTG_AURA_ID = 444661
SRC.AOTG_MAX_HAVOC = 6
SRC.AOTG_MAX = 20 -- Vengeance and Devourer
-- TraitSubTree ID of the Aldrachi Reaver hero talent (TraitTreeID 854 = Demon
-- Hunter), compared against C_ClassTalents.GetActiveHeroTalentSpec(), which
-- returns the active subTreeID.
--
-- NOT a spell ID, and neither is the 117512 that circulated as one: that is Art
-- of the Glaive's TraitNodeEntry ID (TraitDefinition 122524 -> spell 442290,
-- TraitNode 94915). No node walk is needed behind this check -- the talent is
-- GRANTED at rank 1 with the subtree (TraitCond 26662, CondType 2 = Granted),
-- so having Aldrachi Reaver active is having Art of the Glaive.
SRC.AR_SUBTREE_ID = 35

-- Devastation Evoker: Unbound Flame, the charges Dragonrage leaves behind when
-- it ends. Each stack is one cast of the replacement spell, so the strip counts
-- casts remaining, and it decrements rather than builds. An extra row alongside
-- Essence, not a replacement.
--
-- The aura is 1292323, NOT the 1292321 the spell is usually cited by: that id is
-- the castable Unbound Flame (no SpellAuraOptions row, DurationIndex 0), as are
-- 1292322 and 1292325. Only 1292323 carries CumulativeAura = 4 and the 60s
-- duration, and its buff text is the one that reads "Dragonrage changed to
-- Unbound Flame."
--
-- The count is never read -- the aura is secret, so the strip is engine-rendered
-- off a player-bound AuraContainer, same as Wild Imps and Arcane Salvo.
SRC.UNBOUND_FLAME = "UNBOUND_FLAME"
SRC.UNBOUND_FLAME_AURA_ID = 1292323
SRC.UNBOUND_FLAME_MAX_STACKS = 4
-- Rising Fury is a Tiered node (110414) of three entries: 1271687 (1 rank),
-- 1271796 (2 ranks), then 1271788 (1 rank) -- "Dragonrage becomes Unbound
-- Flame". Knowing 1271788 is having all 4 points; without it there is nothing
-- to count.
SRC.RISING_FURY_UNBOUND_TALENT_ID = 1271788

-- Enhancement Shaman: Maelstrom Weapon
SRC.MW_INSTANT_THRESHOLD = 5
-- One entry per client, keyed by the talent that grants it: retail (talent
-- 187880, aura 344179, 10 segments) and WoW Forever 1.60.1 (talent 408498,
-- aura 408505, CumulativeAura 5). A client carries only its own talent, so
-- the first known one wins and nothing branches on the client. The cap is a
-- table value, not the DB2 field: retail's 344179 also reads CumulativeAura 5,
-- and talents raise it to 10 there.
SRC.mwVariants = {
    { talent = 187880, aura = 344179, max = 10 },
    { talent = 408498, aura = 408505, max = 5 },
}

---The Maelstrom Weapon variant the player has talented, or nil.
---@return {talent: integer, aura: integer, max: integer}?
local function getMwVariant()
    for i = 1, #SRC.mwVariants do
        local variant = SRC.mwVariants[i]
        if IsPlayerSpell(variant.talent) then return variant end
    end
    return nil
end

-- Rogue: Coup de Grâce / Escalating Blade
SRC.CDG_BUFF_ID        = 441786
SRC.CDG_MAX_STACKS     = 4

-- Fury Warrior: Improved Whirlwind charges
SRC.WW_MAX_CHARGES = 4
SRC.WW_DURATION    = 20
SRC.WW_TALENT_ID   = 12950
-- Crackling Thunder 203201, Crashing Thunder 436707, Unhinged 386628 — inlined at usage sites

SRC.wwBuilderSpells = {
    [190411] = true, -- Whirlwind
    [6343]   = true, -- Thunder Clap (requires Crackling/Crashing Thunder talent)
    [435222] = true, -- Thunder Blast (requires Crackling/Crashing Thunder talent)
}
SRC.wwSpenderSpells = {
    [23881]  = true, -- Bloodthirst
    [85288]  = true, -- Raging Blow
    [280735] = true, -- Execute
    [202168] = true, -- Impending Victory
    [184367] = true, -- Rampage
    [335096] = true, -- Bloodbath
    [335097] = true, -- Crushing Blow
    [5308]   = true, -- Execute (base ID)
}
SRC.bladestormAuraIDs = {
    [46924]  = true,
    [227847] = true,
    [184362] = true,
    [50622]  = true,
    [446035] = true,
}

-- Paladin: Divine Purpose — the aura-tap candidate filter.
--
-- These are the 12s BUFFs, not the talent passives: 223817 (Holy/Protection)
-- and 408459 (Retribution) are the proc drivers — duration n/a, Apply Aura
-- Dummy, Not In Spellbook — so they never surface as a trackable aura and the
-- filter matches nothing.  223819 is the Holy/Protection buff, 408458 the
-- Retribution one.
--
-- A slot's filter is baked in at bind time and a bound slot can never be
-- re-bound, so the tap filters on every spec's ID rather than the current
-- spec's: behaviorally identical (the buff only exists on the spec being
-- played) and immune to spec changes.
SRC.DIVINE_PURPOSE_BUFF_IDS = {
    [223819] = true,
    [408458] = true,
}

-- Paladin: Crusading Strikes swing timer
SRC.CRUSADING_STRIKES_TALENT = 404542
SRC.CRUSADING_STRIKES_SPELL  = 408385
-- As of 12.1 the talent makes auto-attacks 15% *faster* — period multiplier
-- for the mainhand weapon's base swing speed (1 / 1.15). Single source of
-- truth: the tuning has changed repeatedly (50% slower → 35% → 20% → 15%
-- faster), so only this constant needs to update.
SRC.CRUSADING_STRIKES_PERIOD_FACTOR = 1 / 1.15

-- Paladin: Zealot's Fervor — multiplicative auto-attack-speed talent that
-- isn't reflected in spell haste, so Redemption's castTime sample misses
-- it entirely. Without applying this on top of swingHasteMult, the
-- predicted swing period runs 20%/40% too long for rank 1/2 talented
-- players, the bar fills slowly while real swings come faster, then
-- snaps to 0 on each UNIT_SPELLCAST_SUCCEEDED reset — visibly stuttering.
-- Per-rank bonuses verified against in-game maths: 3.6 mainhand ÷ 1.15
-- (CS) / (1.13 spell haste × 1.40 Zealot rank 2) = 1.979s.
SRC.ZEALOTS_FERVOR_ENTRY_ID = 115165
SRC.ZEALOTS_FERVOR_BONUS    = { [1] = 0.20, [2] = 0.40 }

-- Fire Mage: Fire Blast charges (recharge fill inspired by Henry's OctoChargeBar)
SRC.FIRE_BLAST_SPELL_ID = 108853
SRC.FLAME_ON_SPELL_ID   = 205029

-- Marksmanship Hunter: Aimed Shot charges
SRC.AIMED_SHOT_CHARGES    = "AIMED_SHOT_CHARGES"
SRC.AIMED_SHOT_SPELL_ID   = 19434
SRC.LOCK_AND_LOAD_BUFF_IDS = { [194594] = true }

-- Discipline Priest: Power Word: Radiance charges
SRC.RADIANCE_CHARGES = "RADIANCE_CHARGES"
SRC.RADIANCE_SPELL_ID = 194509
SRC.RADIANCE_DEFAULT_MAX = 2  -- baseline; fallback only if API returns nil before spell is learned

-- Brewmaster Monk: Stagger
-- Stagger debuff aura spell IDs: HEAVY=124273, MODERATE=124274, LIGHT=124275 — inlined at usage sites

-- Monk: Vitality (Aspect of Harmony)
SRC.VITALITY_TALENT_ID = 450508
-- Storing buff aura IDs: LOW=450521, MID=450526, HIGH=450531, SPEND=450769 — inlined at usage sites

-- Evoker: Innate Magic (class-tree passive, +5%/+10% Essence regen rank 1/2)
SRC.INNATE_MAGIC_ENTRY_ID = 115611   -- TraitEntryID; nodeID is resolved at runtime
SRC.INNATE_MAGIC_BONUS    = { [1] = 0.05, [2] = 0.10 }

-- Skyriding Vigor
SRC.VIGOR_SPELL_ID = 372608
SRC.THRILL_OF_THE_SKIES_SPELL_ID = 377234

-- Misc
SRC.DRUID_BEAR_FORM   = 1
SRC.DRUID_CAT_FORM    = 2
SRC.DEFAULT_BAR_GAP   = 2
SRC.druidTravelFormIDs = {[3] = true, [4] = true, [27] = true, [29] = true}

-- Class/spec power mappings
SRC.classSecondaryPower = {
    ROGUE = Enum.PowerType.ComboPoints,
    WARLOCK = Enum.PowerType.SoulShards,
    PALADIN = Enum.PowerType.HolyPower,
    DEATHKNIGHT = Enum.PowerType.Runes,
    EVOKER = Enum.PowerType.Essence,
}

SRC.specSecondaryPower = {
    DRUID = {
        [1] = false,
        [2] = Enum.PowerType.ComboPoints,
        [3] = SRC.IRONFUR_GUARDIAN,
        [4] = false,
    },
    MAGE = {
        [1] = Enum.PowerType.ArcaneCharges,
        [2] = SRC.FIRE_BLAST_CHARGES,
        [3] = SRC.ICICLES_FROST,
    },
    MONK = {
        [3] = Enum.PowerType.Chi,
        [1] = SRC.STAGGER_BREWMASTER,
        [2] = SRC.VITALITY_MONK,
    },
    DEMONHUNTER = {
        [1] = false,
        [2] = SRC.SOUL_FRAG_VENGEANCE,
        [3] = SRC.SOUL_FRAG_DEVOURER,
    },
    WARRIOR = {
        [1] = false,
        [2] = SRC.WW_CHARGES_FURY,
        [3] = false,
    },
    HUNTER = {
        [1] = false,
        [2] = SRC.AIMED_SHOT_CHARGES,
        [3] = SRC.TOTS_CHARGES_SURVIVAL,
    },
    SHAMAN = {
        [1] = false,
        [2] = SRC.MW_CHARGES_ENHANCEMENT,
        [3] = false,
    },
    PRIEST = {
        [1] = SRC.RADIANCE_CHARGES,  -- Discipline
        -- [2] Holy, [3] Shadow: fall through to classSecondaryPower (none)
    },
}

---Whether the player is currently on a skyriding mount (bonus bar 11, offset 5).
local isSkyriding = false

---Returns true when the player is on a skyriding mount.
---Primary check: bonus action bar (reliable during gameplay).
---Fallback: canGlide from GetGlidingInfo (catches login before bonus bar is ready).
local function checkSkyriding()
    if private.inClientScene then
        return false
    end
    local bonusIdx = C_ActionBar.GetBonusBarIndex()
    local bonusOff = C_ActionBar.GetBonusBarOffset()
    local _, canGlide = private.compat.GetGlidingInfo()
    if bonusIdx == 11 and bonusOff == 5 then
        return true
    end
    if canGlide and IsMounted() then
        return true
    end
    -- During mount-up, bonus bar and canGlide can briefly go false while
    -- still mounted. Stay in skyriding state if we were skyriding and the
    -- player is still mounted — a real dismount clears IsMounted().
    if isSkyriding and IsMounted() then
        return true
    end
    return false
end

---Per-spec overrides for classes where only certain specs use a secondary resource.
---false = no secondary resource for that spec; a PowerType value = use that resource.
---Specs not listed for a class fall through to SRC.classSecondaryPower.
---@type table<string, table<integer, integer|string|false>>
SRC.specSecondaryPower = {
    DRUID = {
        [1] = Enum.PowerType.LunarPower,     -- Balance: Astral Power (continuous fill bar)
        [2] = Enum.PowerType.ComboPoints,    -- Feral: combo points
        [3] = SRC.IRONFUR_GUARDIAN,          -- Guardian: Ironfur duration bar
        [4] = false,                         -- Restoration: no combo points by default
    },
    MAGE = {
        [1] = Enum.PowerType.ArcaneCharges, -- Arcane
        [2] = SRC.FIRE_BLAST_CHARGES,            -- Fire: Fire Blast charges
        [3] = SRC.ICICLES_FROST,                 -- Frost: Icicles (timed fill bar)
    },
    MONK = {
        [3] = Enum.PowerType.Chi,            -- Windwalker
        [1] = SRC.STAGGER_BREWMASTER,            -- Brewmaster: Stagger bar (or Vitality via toggle)
        [2] = SRC.VITALITY_MONK,                 -- Mistweaver: Vitality (Aspect of Harmony)
    },
    DEMONHUNTER = {
        [1] = false,                         -- Havoc: no secondary resource
        [2] = SRC.SOUL_FRAG_VENGEANCE,           -- Vengeance: discrete Soul Fragment segments
        [3] = SRC.SOUL_FRAG_DEVOURER,            -- Devourer: fill-bar Soul Fragments
    },
    WARRIOR = {
        [1] = SRC.SWEEPING_STRIKES_ARMS,         -- Arms: Sweeping Strikes stack segments
        [2] = SRC.WW_CHARGES_FURY,               -- Fury: Improved Whirlwind charges
        [3] = SRC.IGNORE_PAIN_PROT,              -- Protection: Ignore Pain absorb bar
    },
    HUNTER = {
        [1] = false,                         -- Beast Mastery: no secondary resource
        [2] = SRC.AIMED_SHOT_CHARGES,            -- Marksmanship: Aimed Shot charges
        [3] = SRC.TOTS_CHARGES_SURVIVAL,         -- Survival: Tip of the Spear stacks
    },
    SHAMAN = {
        [1] = Enum.PowerType.Maelstrom,      -- Elemental: Maelstrom (continuous fill bar)
        [2] = SRC.MW_CHARGES_ENHANCEMENT,        -- Enhancement: Maelstrom Weapon stacks
        [3] = false,                         -- Restoration: no secondary resource
    },
    PRIEST = {
        [1] = SRC.RADIANCE_CHARGES,          -- Discipline: Power Word: Radiance charges
        [3] = Enum.PowerType.Insanity,       -- Shadow: Insanity (continuous fill bar)
        -- [2] Holy: falls through to classSecondaryPower (none)
    },
}

---Cat Form shapeshift index for Druids (GetShapeshiftForm() == 2).
SRC.DRUID_CAT_FORM = 2

---Forward declaration; body assigned after the profile accessor is defined.
---@type fun(): secondaryresources_profile_main
local getSettings

---Returns the secondary power type for the player's current class and specialization.
---Checks SRC.specSecondaryPower first for spec-specific overrides, then falls back to SRC.classSecondaryPower.
---For non-Feral Druids with druid_cat_form enabled, returns ComboPoints when in Cat Form.
---For Brewmaster Monks, returns Stagger only when brewmaster_stagger is enabled.
---@return integer|string|nil powerType The secondary power type, or nil if the class/spec has none.
local getPlayerSecondaryPowerType = function()
    -- Skyriding vigor overrides any class/spec secondary resource while mounted
    if isSkyriding and getSettings().skyriding_vigor then
        return SRC.SKYRIDING_VIGOR
    end

    local _, class = UnitClass("player")
    local specOverrides = SRC.specSecondaryPower[class]
    if specOverrides then
        -- A client with no spec system (Forever) still answers
        -- GetSpecialization(), likely always with 1 (its dual-spec group is
        -- GetActiveSpecGroup), which is not a retail spec index: a shaman read as Elemental and drew
        -- an empty Maelstrom bar. `GetNumSpecializations() <= 1` is the test
        -- PrimaryResources' getRealSpecIndex uses; the class fallback below
        -- takes over.
        local specIndex = GetNumSpecializations() > 1 and C_SpecializationInfo.GetSpecialization()
        if specIndex then
            local specPower = specOverrides[specIndex]
            if specPower == false then
                -- Non-Feral Druids: show combo points when in Cat Form if the option is enabled
                if class == "DRUID" and getSettings().druid_cat_form and GetShapeshiftForm() == SRC.DRUID_CAT_FORM then
                    return Enum.PowerType.ComboPoints
                end
                -- Havoc Demon Hunters: Art of the Glaive is the spec's only
                -- secondary resource, so it claims row 1 as a primary. The same
                -- strip is an extra row on Vengeance and Devourer, which already
                -- have one -- see getActiveResourceTypes.
                if class == "DEMONHUNTER" and getSettings().dh_art_of_glaive_havoc
                    and C_ClassTalents.GetActiveHeroTalentSpec() == SRC.AR_SUBTREE_ID then
                    return SRC.ART_OF_GLAIVE
                end
                return nil
            end
            -- Brewmaster Monks: Vitality overrides Stagger when enabled and talented
            if specPower == SRC.STAGGER_BREWMASTER then
                if getSettings().brewmaster_vitality and IsPlayerSpell(SRC.VITALITY_TALENT_ID) then
                    return SRC.VITALITY_MONK
                end
                if not getSettings().brewmaster_stagger then return nil end
            end
            -- Mistweaver Monks: Vitality requires the toggle and the talent.
            -- Teachings of the Monastery, when toggled and talented, takes the
            -- Mistweaver secondary slot over Vitality.
            if specPower == SRC.VITALITY_MONK then
                if getSettings().mistweaver_teachings and IsPlayerSpell(SRC.TOTM_TALENT_ID) then
                    return SRC.TEACHINGS_MONK
                end
                if not getSettings().mistweaver_vitality then return nil end
                if not IsPlayerSpell(SRC.VITALITY_TALENT_ID) then return nil end
            end
            -- Protection Warriors: Ignore Pain requires the toggle
            if specPower == SRC.IGNORE_PAIN_PROT then
                if not getSettings().protection_ignore_pain then return nil end
            end
            -- Arms Warriors: Sweeping Strikes requires the toggle and the talent
            if specPower == SRC.SWEEPING_STRIKES_ARMS then
                if not getSettings().arms_sweeping_strikes then return nil end
                if not IsPlayerSpell(SRC.SS_TALENT_ID) then return nil end
            end
            -- Fury Warriors: Whirlwind charges require the toggle and the talent
            if specPower == SRC.WW_CHARGES_FURY then
                if not getSettings().fury_whirlwind then return nil end
                if not IsPlayerSpell(SRC.WW_TALENT_ID) then return nil end
            end
            -- Survival Hunters: Tip of the Spear requires the toggle and the talent
            if specPower == SRC.TOTS_CHARGES_SURVIVAL then
                if not getSettings().survival_tip_of_the_spear then return nil end
                if not IsPlayerSpell(SRC.TOTS_TALENT_ID) then return nil end
            end
            -- Enhancement Shamans: Maelstrom Weapon requires the toggle and the talent
            if specPower == SRC.MW_CHARGES_ENHANCEMENT then
                if not getSettings().enhancement_maelstrom_weapon then return nil end
                if not getMwVariant() then return nil end
            end
            -- Fire Mages: Fire Blast charges require the toggle
            if specPower == SRC.FIRE_BLAST_CHARGES then
                if not getSettings().fire_blast_charges then return nil end
            end
            -- Marksmanship Hunters: Aimed Shot charges require the toggle
            if specPower == SRC.AIMED_SHOT_CHARGES then
                if not getSettings().marksman_aimed_shot then return nil end
            end
            -- Discipline Priests: Power Word: Radiance charges require the toggle
            if specPower == SRC.RADIANCE_CHARGES then
                if not getSettings().discipline_radiance_charges then return nil end
            end
            -- Frost Mages: Icicles require the toggle
            if specPower == SRC.ICICLES_FROST then
                if not getSettings().frost_icicles then return nil end
            end
            -- Guardian Druids: only show Ironfur in Bear Form; fall through to cat-form combo points
            if specPower == SRC.IRONFUR_GUARDIAN then
                local form = GetShapeshiftForm()
                if form == SRC.DRUID_BEAR_FORM and getSettings().guardian_ironfur then
                    return SRC.IRONFUR_GUARDIAN
                end
                if form == SRC.DRUID_CAT_FORM and getSettings().druid_cat_form then
                    return Enum.PowerType.ComboPoints
                end
                return nil
            end
            -- Balance Druids: Astral Power is the secondary (DRUID[1]), but honor the
            -- druid_cat_form cat-weaving override that the false→LunarPower change would
            -- otherwise bypass (the specPower == false branch above no longer fires).
            if class == "DRUID" and specIndex == 1 and getSettings().druid_cat_form
                and GetShapeshiftForm() == SRC.DRUID_CAT_FORM then
                return Enum.PowerType.ComboPoints
            end
            if specPower then return specPower end
        end
    end
    -- No spec to key on (no spec system, or retail's initial spec): Cat Form
    -- combo points are a class feature, and on Forever this is the path that
    -- used to reach them through the misread Balance entry above.
    if class == "DRUID" and getSettings().druid_cat_form and GetShapeshiftForm() == SRC.DRUID_CAT_FORM then
        return Enum.PowerType.ComboPoints
    end
    -- Maelstrom Weapon is a talent, not a spec, where there is no spec to key on
    -- (Forever). Retail reaches it through the Enhancement entry above, and a
    -- retail character on its initial spec has no talents to land here with.
    if class == "SHAMAN" and getSettings().enhancement_maelstrom_weapon and getMwVariant() then
        return SRC.MW_CHARGES_ENHANCEMENT
    end
    return SRC.classSecondaryPower[class]
end

---Cached player class token. A character's class cannot change, so this is a
---one-shot value cache, not a caching layer — the same shape `Components/CastBar.lua`
---uses. It exists so `getActiveResourceTypes` does not pay a second
---`UnitClass("player")` on every Refresh, on top of the one
---`getPlayerSecondaryPowerType` has just made.
---@type string?
local playerClass = select(2, UnitClass("player"))

---Scratch list of the resource types to display simultaneously, primary first.
---Rewritten in place on every call rather than rebuilt, so the Refresh path
---allocates nothing. `hasPrimary` is false when entry 1 is an extra standing in
---for a primary the spec has switched off.
---@type (integer|string)[]|{hasPrimary: boolean}
local activeResourceTypes = {}

---Returns the ordered list of resource types to display simultaneously, and how
---many there are — one row per entry.
---
---Entry 1 is the primary when the spec has one: `getPlayerSecondaryPowerType`
---stays the single owner of every per-spec toggle and talent gate, and this only
---decides how many rows that answer expands into. Extra resources (a Mage Arcane
---Salvo bar beside Arcane Charges, a Shatter bar beside Icicles) append AFTER the
---primary, so row 1 keeps rendering exactly what the single-resource code
---rendered before. With no primary (a Frost Mage with Icicles off) the first
---extra takes row 1, and `types.hasPrimary` is false so row 1 does not claim the
---primary's `resource = nil` thresholds.
---
---The returned table is module-owned scratch — read it before the next call.
---@return (integer|string)[] types
---@return integer count
local getActiveResourceTypes = function()
    local count = 0
    local primary = getPlayerSecondaryPowerType()
    -- A real power type with no maximum is a resource the character does not
    -- have (a Forever class without it, a level below the one that unlocks it).
    -- Resolving it away rather than drawing zero segments is what makes
    -- GetEnabled() false, so Anchoring skips the component the way it skips a
    -- spec with no resource instead of keeping an empty frame in the chain.
    -- The UNIT_MAXPOWER handler on talentEventFrame brings it back. Sentinel
    -- resources are strings and gate on their own talent or setting.
    if type(primary) == "number" and UnitPowerMax("player", primary) <= 0 then
        primary = nil
    end
    if primary then
        count = 1
        activeResourceTypes[1] = primary
    end
    activeResourceTypes.hasPrimary = primary ~= nil
    -- Extra rows. These are additions to the spec's primary, never replacements,
    -- so each is gated on its own setting here rather than in
    -- getPlayerSecondaryPowerType (which resolves the primary only). Order is
    -- the row order. Keep extras engine-driven: the eleven dedicated
    -- per-resource event frames still write to row 1, but only for their own
    -- primary resource, so an extra needing one could not live in any row.
    --
    -- With no primary the first extra lands in row 1. The transition paths
    -- resolve playerPowerType from this list for that reason, not from
    -- getPlayerSecondaryPowerType.
    --
    -- Skyriding takes the whole component: `getPlayerSecondaryPowerType` returns
    -- SKYRIDING_VIGOR as the primary, and a class resource has nothing to say
    -- while mounted. Gating the block rather than each entry — every extra has
    -- the same nothing to say, and each one's own gate (class, spec, talent,
    -- setting) is still true in the air, so before this they all kept their row.
    if primary ~= SRC.SKYRIDING_VIGOR then
        -- Same no-spec-system test as getPlayerSecondaryPowerType: Forever's
        -- GetSpecialization() 1 must not read as Arcane.
        local specIndex = GetNumSpecializations() > 1 and C_SpecializationInfo.GetSpecialization()
        if playerClass == "MAGE" and getSettings().mage_shatter_stacks
            and specIndex == 3 then
            count = count + 1
            activeResourceTypes[count] = SRC.SHATTER_FREEZING
        end
        if playerClass == "WARLOCK" and getSettings().warlock_wild_imps
            and specIndex == 2 then
            count = count + 1
            activeResourceTypes[count] = SRC.WILD_IMPS_DEMO
        end
        if playerClass == "MAGE" and getSettings().mage_arcane_salvo_stacks
            and specIndex == 1 then
            count = count + 1
            activeResourceTypes[count] = SRC.ARCANE_SALVO
        end
        if playerClass == "EVOKER" and getSettings().evoker_unbound_flame
            and specIndex == 1 and IsPlayerSpell(SRC.RISING_FURY_UNBOUND_TALENT_ID) then
            count = count + 1
            activeResourceTypes[count] = SRC.UNBOUND_FLAME
        end
        -- Every DH spec. Havoc (1) was left out while an extra needed a primary
        -- to sit beside; it now takes row 1 on its own, or row 2 under Art of
        -- the Glaive (user decision 2026-09-23).
        if playerClass == "DEMONHUNTER" and getSettings().dh_nearby_souls then
            local dhSpec = C_SpecializationInfo.GetSpecialization()
            if dhSpec == 1 or dhSpec == 2 or dhSpec == 3 then
                count = count + 1
                activeResourceTypes[count] = SRC.NEARBY_SOULS_DH
            end
        end
        -- Vengeance (2) and Devourer (3) only -- Havoc takes Art of the Glaive
        -- as its primary instead (getPlayerSecondaryPowerType), because it has
        -- no other secondary resource for an extra to sit beside. All three
        -- gate on the same hero spec; only the enable setting and the cap
        -- differ.
        if playerClass == "DEMONHUNTER"
            and C_ClassTalents.GetActiveHeroTalentSpec() == SRC.AR_SUBTREE_ID then
            local dhSpec = C_SpecializationInfo.GetSpecialization()
            if (dhSpec == 2 and getSettings().dh_art_of_glaive_vengeance)
                or (dhSpec == 3 and getSettings().dh_art_of_glaive_devourer) then
                count = count + 1
                activeResourceTypes[count] = SRC.ART_OF_GLAIVE
            end
        end
    end
    for i = count + 1, #activeResourceTypes do
        activeResourceTypes[i] = nil
    end
    return activeResourceTypes, count
end

---Power types that update via UNIT_POWER_FREQUENT (discrete, non-time-based resources).
---Runes and Essence use GetTime()-based OnUpdate fills instead.
---@type table<integer, boolean>
SRC.staticPowerTypes = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ArcaneCharges] = true,
}

---The powerTypeToken string sent by UNIT_POWER_FREQUENT and UNIT_MAXPOWER for each
---secondary resource. Tokens match the PowerBarColor table keys (Blizzard convention).
---Used to filter out unrelated power events (e.g. Mana events on Evokers/Rogues).
---@type table<integer, string>
SRC.powerTypeTokens = {
    [Enum.PowerType.ComboPoints] = "COMBO_POINTS",
    [Enum.PowerType.SoulShards] = "SOUL_SHARDS",
    [Enum.PowerType.HolyPower] = "HOLY_POWER",
    [Enum.PowerType.Chi] = "CHI",
    [Enum.PowerType.ArcaneCharges] = "ARCANE_CHARGES",
    [Enum.PowerType.Runes] = "RUNES",
    [Enum.PowerType.Essence] = "ESSENCE",
    [Enum.PowerType.Maelstrom] = "MAELSTROM",
    [Enum.PowerType.LunarPower] = "LUNAR_POWER",
    [Enum.PowerType.Insanity] = "INSANITY",
}

---True where combo points sit on the target (WoW Forever and every classic
---client): there the player's points are the ones on the current target, and
---Blizzard's combo frame reads `GetComboPoints(unit, "target")` (Forever
---`Mainline/ComboFrame.lua`, classic `Classic/ComboFrame.lua`). Retail keeps
---`UnitPower`, since `GetComboPoints` reads 0 there without a hostile target.
---No API names the rule; Blizzard decides it by which unit-frame files load.
---Only retail loads the player-side `RogueComboPointBar` (Forever excludes it
---for camelot in `Blizzard_UnitFrame.toc`, classic clients load
---`Blizzard_UnitFrame_Classic.toc`, which has none), so its frame is the probe.
---Blizzard_UnitFrame loads before any addon.
SRC.comboPointsOnTarget = RogueComboPointBarFrame == nil

---Current value of a whole-unit static resource (`SRC.staticPowerTypes`).
---@param powerType integer
---@return number
SRC.staticPower = function(powerType)
    if powerType == Enum.PowerType.ComboPoints and SRC.comboPointsOnTarget then
        return GetComboPoints("player", "target")
    end
    return UnitPower("player", powerType)
end

---Continuous (0–max) power types rendered as a single fill bar instead of discrete pips.
---Real Enum.PowerType values relocated here from the primary bar for caster
---builder/spenders (Elemental Maelstrom, Balance Astral Power, Shadow Insanity).
---NOT in staticPowerTypes — that path renders one pip per point (max-100 → 100 pips).
---@type table<integer, boolean>
SRC.continuousBarPowers = {
    [Enum.PowerType.Maelstrom] = true,
    [Enum.PowerType.LunarPower] = true,
    [Enum.PowerType.Insanity] = true,
}

SRC.DEFAULT_BAR_GAP = 2

-- ── Demon Hunter Soul Fragment helpers ───────────────────────────────────────

---Returns the current Vengeance Soul Fragment count via C_Spell.GetSpellCastCount.
local getVengeanceSoulFragments = function()
    return C_Spell.GetSpellCastCount(SRC.VENG_SOUL_FRAG_SPELL) or 0
end

---Returns the current Devourer soul count via C_Spell.GetSpellCastCount.
local getDevourerSoulCount = function()
    return C_Spell.GetSpellCastCount(1217605) or 0 -- Void Metamorphosis
end

---Returns the Devourer max soul cap based on Metamorphosis and Soul Glutton state.
---Default 50; 35 with Soul Glutton talent; 40 during Void Metamorphosis.
local getDevourerSoulMax = function()
    local isInMeta = C_UnitAuras.GetPlayerAuraBySpellID(1217607) ~= nil -- Void Metamorphosis buff
    if isInMeta then return 40 end
    local hasSoulGlutton = C_SpellBook.IsSpellKnown(1247534) -- Soul Glutton
    if hasSoulGlutton then return 35 end
    return 50
end

---Cached Devourer max soul cap, updated on Metamorphosis/talent changes.
---@type integer
local cachedDevourerMax = 50

---Cached soul fragment counts, updated by their respective update functions.
---Used by updateValueText to avoid redundant C_Spell.GetSpellCastCount calls.
---@type integer
local cachedVengeanceFragments = 0
---@type integer
local cachedDevourerSouls = 0

-- ── Devourer Reap forecast (Reaper Soul Tracker integration) ─────────────
-- Overlays the existing soul bar with a Reap-consumption preview that anchors
-- to the bar's fill edge and extends rightward by reapCap's share of the bar
-- width. MoC capacity (4 vs 10) detected via the Reap → Eradicate spell
-- override (1226019 → 1225826), not the MoC aura. The "(+nearby)" suffix on
-- the soul-bar value text reads a SECRET Soul Fragment applications value via
-- the CDM BuffIcon child IID and pipes it directly into SetFormattedText("%d").
-- Packed into one local to respect Lua 5.1's 200-local limit.
local reapFc = {
    -- Soul Fragment / Shattered Souls aura IDs. CDM may surface any of these
    -- depending on the user's tracked-buffs config; applications are secret
    -- (pre-12.1: read via instance ID; 12.1: Blizzard renders the count into
    -- the bound tap FontString, display-only — see reapFc.ensureTapStacks).
    sfIds = {
        [1245577] = true, [1245584] = true, [203981] = true, [210788] = true,
        [1227619] = true,
    },
    -- Collapsing Star cast threshold (30 souls). Shown only during Void
    -- Metamorphosis, since CS is the VM-phase ability.
    pipCSThreshold = 30,
    -- Highest value getCap can return. The 12.1 ammo bar binds at this FIXED
    -- max instead of the live cap, so its scale never needs a re-bind — see
    -- reapFc.updateTapAmmo for why a cap-scaled bind could never converge.
    capMax = 10,
    -- Lazy-created overlays on resourceFrames[1].
    clipFrame = nil,  ---@type Frame?     Clipping container that masks slab overflow past the bar's right edge near max souls (avoids reading any secret-tainted geometry).
    ammoClip = nil,   ---@type Frame?     Clip frame sized to the LIVE cap width; masks the fixed-capMax ammo bar down to what Reap would actually consume.
    ammoBaked = nil,  ---@type number?    fullWidthPx the ammo BUTTON was last sized to. The soul→pixel scale is baked into that width and the button is unwritable in combat, so ammoClip:SetScale corrects for any later move in barWidth or cachedDevourerMax.
    preview = nil,    ---@type Texture?   Reap preview slab at the soul-fill edge.
    pipCS = nil,      ---@type Texture?   Collapsing Star cast threshold marker.
    capPoll = nil,    ---@type cbObject?  Ticker that polls the Reap override while the cap reads 10. The override is the only readable MoC signal (the aura is hidden and secret), so this is the sole path back to a cap of 4.
}

-- ── 12.1 secret-aura access (safe instance-ID reads + aura-slot data tap) ───
-- 12.1 makes instance-ID C_UnitAuras APIs Lua-error from addon code while
-- auras are secret (combat/encounters/M+/PvP) — see .context/patterns-secrets.md
-- "12.1 Aura Lockdown". Everything packed into one local (200-local ceiling,
-- same convention as reapFc).
local auraTap = {
    container = nil,     ---@type Frame?  invisible CustomAuraContainer host
    slots = {},          ---@type table<string, FontString>  slotKey -> bound FS
    bars = {},           ---@type table<string, StatusBar> slotKey -> bound application bar
    barButtons = {},     ---@type table<string, Frame> slotKey -> slot button (geometry host)
    barContainers = {},  ---@type table<string, Frame> slotKey -> dedicated bar container
    glows = {},          ---@type table<string, Frame> slotKey -> unbound border child
    fills = {},          ---@type table<string, Texture> slotKey -> unbound fill child
    glowContainers = {}, ---@type table<string, Frame> slotKey -> dedicated glow/fill container
    pandemics = {},      ---@type table<string, Frame> slotKey -> registered pandemic host (see ensurePandemic)
    pipSets = {},        ---@type table<string, table> key -> discrete-pip strip (see ensurePips)
    borderSets = {},     ---@type table<string, table> key -> animated threshold border (see ensureBorder)
    borderSigs = {},     ---@type table<string, number> key -> the signature borderSets[key] was built for
    rowKeys = {},        ---@type table<string, table<integer, string>> base key -> row index -> row-scoped key (see tapKeyForRow)
}

---True while instance-ID aura reads would Lua-error from addon code (12.1+
---with auras secret: combat/encounters/M+/PvP). C_Secrets.ShouldAurasBeSecret
---is argument-free, returns a plain bool and is callable from tainted code —
---the deterministic runtime gate.
auraTap.blocked = function()
    return C_Secrets.ShouldAurasBeSecret()
end

---Creates (once) an AuraContainer plus a dedicated aura slot whose button
---binds a FontString via SetApplicationCount — Blizzard's secure path then
---writes the aura's stack count into it as SECRET text and the engine renders
---it (display-only composition; a pass-through NumericRuleFormatter makes 0
---and 1 render too — Blizzard's formatter-less default is "" below 2).
---The FontString MUST be created ON the button: the bind
---validates "must inherit all forbidden parent aspects from owner"
---(Blizzard_CustomAuraButton.lua:25), so a region parented elsewhere is
---rejected. Positioning is done via CROSS-FRAME ANCHORING from configureFn —
---a region renders at its anchor target regardless of its parent's position.
---The container is visible (the Custom button template is a blank shell; only
---bound elements render) so the text isn't alpha-zeroed by its parent chain.
---After binding, the FS is forbidden to tainted code while auras are secret —
---never GetText/SetShown/SetFont it in combat; see patterns-secrets.md.
---configureFn(fs) runs BEFORE the bind (font/anchor/color setup; the bind
---pushes text immediately and a font-less SetText errors "Font not set").
---No-op in combat (container creation Lua-errors there by design) — callers
---re-invoke from update ticks, so the first out-of-combat tick retries.
auraTap.ensure = function(slotKey, spellIDMap, configureFn)
    if auraTap.slots[slotKey] or not configureFn
        or InCombatLockdown() then
        return
    end
    if not auraTap.container then
        local c = LAC:CreateContainer("CUE_SR_AuraTap", UIParent)
        c:SetUnit("player")
        c:SetSize(1, 1)
        c:SetPoint("CENTER")
        c:SetFrameStrata("HIGH")
        c:SetEnabled(true)
        c:Show()
        auraTap.container = c
        auraTap.syncAlpha()
    end
    auraTap.container:AddAuraSlot(slotKey, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spellIDMap },
        initializeFrame = function(button)
            -- Runs once at slot-frame CREATION (slots use a dedicated
            -- batchSize=1 provider). configureFn runs PRE-BIND (font styling
            -- only — NO anchoring in this context, it errors; anchors come
            -- from applyTapAnchors later). The font object must be set before
            -- the bind (it pushes text immediately and a font-less SetText
            -- errors "Font not set").
            local fs = button:CreateFontString(nil, "OVERLAY")
            fs:SetFontObject(GameFontNormal)
            configureFn(fs)
            -- Pass-through formatter: one breakpoint from 0 rendering "(%d)"
            -- — bracketed, and counts of 0/1 render too (Blizzard's
            -- formatter-less default is "" below 2). Known issue: addon-created formatters
            -- currently reject the secret applications value ("Attempt to set
            -- secret values on an object that prevents secret values", no
            -- taint, live 2026-07-21) — reportedly fixed in the next patch;
            -- until then the count may not render while secret.
            local fmt = C_StringUtil.CreateNumericRuleFormatter()
            fmt:AddBreakpoint({ threshold = 0, format = "(%d)" })
            button:SetApplicationCount(fs, { formatter = fmt })
            auraTap.slots[slotKey] = fs
        end,
    })
end

---Creates (once) a DEDICATED AuraContainer + slot whose button binds a
---StatusBar via SetApplicationBar — Blizzard then drives
---SetMinMaxValues(0, maxApplications) + SetValue(secret applications) on
---every aura update, engine-side (Blizzard_CustomAuraButton.lua
---ApplyApplicationBar). maxApplications is MANDATORY: nil Lua-errors in the
---first display update (math.max(nil, 1)).
---
---Geometry model (source-derived, PTR-verify): slot buttons are NOT in the
---container flow layout (groups only), so the button has no rect until WE
---anchor it — allowed out of combat because the button's access restriction
---is DenyTaintedAccessWhenAurasAreSecret. The bar is created ON the button
---(bind requires inheriting the button's forbidden parent+layout aspects),
---anchored in-family via SetAllPoints(button) AFTER the synchronous
---AddAuraSlot return (SetPoint inside initializeFrame errors
---UntrustedLayoutScriptExecution). Callers position/size the BUTTON from
---their update path via auraTap.barButtons[slotKey], gated on not blocked().
---The button self-hides while no matching aura is active (ApplyVisibility,
---secret Shown) — the bar vanishes with it, no addon-side hide needed.
---The container gets its own parent (pass a clip frame for overflow
---masking); its position is irrelevant to the button, which anchors to
---caller frames directly. No-op in combat; callers re-invoke from update
---ticks.
auraTap.ensureBar = function(slotKey, spellIDMap, parent, maxApplications, configureFn)
    if auraTap.bars[slotKey] or not parent
        or InCombatLockdown() then
        return
    end
    local c = LAC:CreateContainer("CUE_SR_AuraTapBar_" .. slotKey, parent)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    maxApplications = math.max(maxApplications or 1, 1)
    local button = c:AddAuraSlot(slotKey, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spellIDMap },
        initializeFrame = function(btn)
            -- PRE-BIND: parent + styling only, NO anchors in this context.
            local bar = CreateFrame("StatusBar", nil, btn)
            if configureFn then configureFn(bar) end
            btn:SetApplicationBar(bar, { maxApplications = maxApplications })
            auraTap.bars[slotKey] = bar
        end,
    })
    auraTap.barContainers[slotKey] = c
    auraTap.barButtons[slotKey] = button
    -- In-family anchor after the synchronous AddAuraSlot return — the bar
    -- fills the button; the button's rect is the caller's to define.
    auraTap.bars[slotKey]:SetAllPoints(button)
end

---Creates (once) a dedicated AuraContainer holding N slots — one per pip — each
---binding its own StatusBar via SetApplicationBar at the SAME
---`maxApplications`, which defaults to `n`. The engine fills every bar to
---`applications / maxApplications` of ITS OWN length, so with the default a bar
---made n pips long and clipped to pip i's rect shows exactly the slice
---[i-1, i]: full at i stacks or more, empty below i-1.
---That is the old `SetMinMaxValues(i - 1, i)` + `SetValue(stacks)` pip
---decomposition with the addon-side read removed — and the read is what died
---when auras went secret (the instance-ID read returned nil for the whole of
---every pull, so a discrete stack strip sat at 0 exactly when it mattered).
---
---Decoupling the two is what makes the segmentation optional: at `n = 1` with
---`maxApplications` left at the aura's cap, `layoutPips`' geometry collapses to
---a single host-sized bar filled to `stacks / cap` — one continuous fill,
---through this same plumbing. No second renderer, and `layoutPips` /
---`stylePips` / `setPipsShown` need no branch for it.
---
---ONE container, N slots: `AuraContainerAuraSlotManagerMixin:AddAura` walks
---every slot independently (`Blizzard_AuraContainerSlots.lua`), so N slots may
---all match the same aura, and slots sharing a filter string share a single
---aura parse — an 18-pip Arms strip costs one parse, not eighteen.
---
---The clip sits BETWEEN button and bar: `ValidateInboundScriptObject` accepts
---any descendant of the owner ("must be a direct child or indirect
---descendent", `Blizzard_AuraContainerUtil.lua:265`), not only a direct child,
---so the bar stays bindable from inside it.
---
---A change to EITHER `n` or `maxApplications` RELEASES the set — a bound bar can
---never be re-bound (`GetValidatedForbiddenObjectTable` rejects
---access-constrained objects) — and the caller's next pass rebuilds it, leaking
---the abandoned container once per flip (talent changes, out of combat). Both
---have to be in the guard: with segmentation off `n` is pinned at 1 while the
---cap still moves (Sweeping Strikes flips 12 ⇄ 18 on a talent change), so an
---`n`-only guard would leave the bar scaled to the old cap forever.
---Geometry is NOT set here: pip size comes from the host frames, so
---`auraTap.layoutPips` owns it and re-runs from every layout pass.
---No-op in combat / while auras are secret; callers re-invoke every pass.
---@param key string
---@param spellIDMap table<number, boolean>
---@param n integer  rendered segment count — the aura's max stacks, or 1 for one continuous fill
---@param parent Frame
---@param configureFn fun(bar: StatusBar)?  pre-bind styling
---@param unit string?  defaults to "player"
---@param filter string?  defaults to "HELPFUL"
---@param maxApplications integer?  aura cap the engine scales the fill to; defaults to `n`
---@return table? set
auraTap.ensurePips = function(key, spellIDMap, n, parent, configureFn, unit, filter, maxApplications, wantCount)
    local set = auraTap.pipSets[key]
    maxApplications = maxApplications or n
    if set and set.n == n and set.maxApplications == maxApplications then return set end
    if not parent or n < 1
        or InCombatLockdown() or auraTap.blocked() then
        -- Never release what we cannot rebuild in the same pass, or
        -- a cap flip mid-pull would blank the strip for the rest of it. The
        -- stale-scale set keeps rendering until the first writable pass.
        return set
    end
    if set then
        set.container:SetEnabled(false)
        set.container:Hide()
        auraTap.pipSets[key] = nil
    end
    unit = unit or "player"
    filter = filter or "HELPFUL"
    local c = LAC:CreateContainer("CUE_SR_PipTap_" .. key, parent)
    c:SetUnit(unit)
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    set = { container = c, n = n, maxApplications = maxApplications, buttons = {}, clips = {}, bars = {} }
    for i = 1, n do
        set.buttons[i] = c:AddAuraSlot(key .. i, filter, {
            candidateFilters = { includeSpellIDs = spellIDMap },
            initializeFrame = function(btn)
                -- PRE-BIND: creation + styling only, NO anchors or clipping in
                -- this context (SetPoint errors under
                -- UntrustedLayoutScriptExecution); both come after the return.
                local clip = CreateFrame("Frame", nil, btn)
                local bar = CreateFrame("StatusBar", nil, clip)
                -- The pip index is passed so a caller can color pip i by its own
                -- position. That is the only threshold semantic a stack strip can
                -- carry: the count is secret, but the engine shows pip i only at
                -- stacks >= i, so a static per-pip color is exactly "from this
                -- stack upward" with no false coloring below the threshold.
                if configureFn then configureFn(bar, i) end
                btn:SetApplicationBar(bar, { maxApplications = maxApplications })
                set.clips[i] = clip
                set.bars[i] = bar
            end,
        })
    end
    -- Post-return, the same moment ensureBar anchors its bar: the clips mask
    -- each bar down to its own slice once layoutPips gives them a rect.
    for i = 1, n do
        set.clips[i]:SetClipsChildren(true)
    end
    -- The count readout rides THIS container rather than the shared player one in
    -- auraTap.ensure, which is fixed at SetUnit("player") + "HELPFUL". That is the
    -- whole reason a target-bound strip (Shatter) could never have a number: it is
    -- not a limit of the readout, only of the container it used to live on. Here it
    -- inherits the strip's own unit and filter, and — the part that matters — the
    -- SAME container the friendly-target gate in shatterState.syncTarget disables,
    -- so a skipped identity filter can never leave a junk count on screen while the
    -- pips are correctly dark. A second container would need that gate kept in
    -- lockstep, which is exactly the drift `.context/api.md` warns about.
    -- One extra slot, not in `buttons`, so layoutPips never touches it; the caller
    -- anchors the FontString itself.
    if wantCount then
        set.countBtn = c:AddAuraSlot(key .. "count", filter, {
            candidateFilters = { includeSpellIDs = spellIDMap },
            initializeFrame = function(btn)
                -- PRE-BIND, so styling only — no anchors here (they error under
                -- UntrustedLayoutScriptExecution). The font object must be set
                -- before the bind, which pushes text immediately.
                local fs = btn:CreateFontString(nil, "OVERLAY")
                fs:SetFontObject(GameFontNormal)
                -- Plain "%d", not auraTap.ensure's "(%d)": that bracketed form is a
                -- SUFFIX for the Devourer soul bar's "(+nearby)" readout, and a
                -- strip's count only ever wore it by sharing that function.
                local fmt = C_StringUtil.CreateNumericRuleFormatter()
                fmt:AddBreakpoint({ threshold = 0, format = "%d" })
                btn:SetApplicationCount(fs, { formatter = fmt })
                set.countText = fs
            end,
        })
    end
    auraTap.pipSets[key] = set
    return set
end

---Positions a pip set. Button i covers `hostFn(i)` — the one cross-frame edge
---per pip, and a LIVE anchor, so it tracks host resizes with no further writes.
---The clip is in-family on the button; the bar is n pips long inside it and slid
---back by (i - 1) pips so its own slice lands in the window. Horizontal strips
---run left→right and vertical ones bottom→top, matching `layoutBars`.
---
---w/h are the PIP's size and are passed in rather than read back: the last host
---in a strip is two-point-anchored, so its `GetWidth` is stale in the same
---frame. The virtual strip is n pips long with NO gaps, which is what keeps the
---slice boundaries exact — spanning the real strip instead would put boundary i
---one gap to the right of pip i's edge.
---
---Every write here is blocked while auras are secret, so callers re-invoke from
---their layout path and the first writable pass converges.
---@param key string
---@param hostFn fun(i: integer): Region?  the rect pip i should cover
---@param w number  pip width
---@param h number  pip height
---@param vertical boolean
auraTap.layoutPips = function(key, hostFn, w, h, vertical)
    local set = auraTap.pipSets[key]
    if not set or InCombatLockdown() or auraTap.blocked() then return end
    local first = hostFn(1)
    if not first then return end
    set.container:SetFrameLevel(first:GetFrameLevel() + 1)
    -- A pip's fill sits three levels above the container (button > clip > bar) while
    -- the count slot is a bare child at container + 1, so the number rendered behind
    -- the bars. Nothing anchors this button, only its level matters.
    if set.countBtn then
        set.countBtn:SetFrameLevel(set.container:GetFrameLevel() + 5)
    end
    for i = 1, set.n do
        local host, bar, clip = hostFn(i), set.bars[i], set.clips[i]
        local btn = set.buttons[i]
        if not (host and bar and clip and btn) then break end
        btn:ClearAllPoints()
        btn:SetAllPoints(host)
        clip:ClearAllPoints()
        clip:SetAllPoints(btn)
        bar:ClearAllPoints()
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if vertical then
            bar:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, -(i - 1) * h)
            bar:SetSize(w, h * set.n)
        else
            bar:SetPoint("TOPLEFT", clip, "TOPLEFT", -(i - 1) * w, 0)
            bar:SetSize(w * set.n, h)
        end
    end
end

---Re-styles a pip set's bound bars. They are bound objects, so the write only
---lands while auras are non-secret; a mid-combat colour change converges on the
---next out-of-combat pass. Callers gate on `auraTap.blocked()` before building
---the closure so the hot path allocates nothing.
---@param key string
---@param styleFn fun(bar: StatusBar, i: integer)
auraTap.stylePips = function(key, styleFn)
    local set = auraTap.pipSets[key]
    if not set or auraTap.blocked() then return end
    for i = 1, set.n do
        if set.bars[i] then styleFn(set.bars[i], i) end
    end
end

---Shows or hides a pip set. The container is a plain addon frame, so this is
---ungated — the bound bars follow it.
---@param key string
---@param shown boolean
auraTap.setPipsShown = function(key, shown)
    local set = auraTap.pipSets[key]
    if set then set.container:SetShown(shown) end
end

---Border thickness in pixels. ponytail: fixed rather than a profile key -- a border
---this thin has no useful range, and nobody has asked for one.
local BORDER_THICKNESS = 2

---Builds (once per signature) the animated threshold border for a stack strip, or tears
---an existing one down when `runs` is nil. Returns the set, or nil when there is none.
---
---**Why a bound fill and not a border frame.** An aura slot button is shown on aura
---PRESENCE (`SetShown(secretwrap(auraData ~= nil))`, `Blizzard_CustomAuraButton.lua:576`)
---and no candidate filter tests `applications` (`Blizzard_AuraContainerUtil.lua:48` --
---spellIDs, dispel types, boss/role/priority/stealable flags, `maxDuration`, nameplate
---flags, and nothing else). So an ordinary backdrop or texture child would light at one
---stack and stay lit for the whole aura. The engine drives exactly one thing from the
---protected count -- `statusBar:SetValue(applications)` in `ApplyApplicationBar` -- so
---the cue has to BE a fill.
---
---**The reveal is `ensurePips`' trick against a wider window.** Each edge is a clip
---holding a bar `cap` windows long, slid back `(value - 1)` windows, so the fill's
---leading edge sits at `windowStart + (applications - value + 1) * windowLen`: clear of
---the window below `value`, exactly covering it at `value`. Position-independent, which
---is what lets one formula serve both a whole-bar border and a run of one.
---
---**Runs never overlap, and that is the point.** Layering one whole-bar overlay per
---threshold was the first design and it is wrong twice over: additive layers sum instead
---of overriding, and the pulse takes alpha below 1, so a lower layer bleeds through the
---upper. Each threshold instead owns the stretch from the PREVIOUS threshold's boundary
---to its own, so nothing is ever drawn over anything else and every threshold keeps its
---own colour. With a single threshold that stretch is the whole bar.
---@param key string
---@param spellIDMap table<number, boolean>
---@param runs table[]?  from stackThresholdRuns; nil tears the border down
---@param cap integer
---@param parent frame?
---@param unit string?
---@param filter string?
---@param sig number  rebuild fingerprint, stored so a declined pass retries
---@return table?
auraTap.ensureBorder = function(key, spellIDMap, runs, cap, parent, unit, filter, sig)
    if auraTap.borderSigs[key] == sig then return auraTap.borderSets[key] end
    -- Never tear down what cannot be rebuilt in the same pass, and leave the signature
    -- unstamped so the next writable pass tries again. Same contract as ensurePips.
    if not parent or InCombatLockdown() or auraTap.blocked() then
        return auraTap.borderSets[key]
    end
    local old = auraTap.borderSets[key]
    if old then
        if old.pulse then old.pulse:Stop() end
        old.container:SetEnabled(false)
        old.container:Hide()
        auraTap.borderSets[key] = nil
    end
    auraTap.borderSigs[key] = sig
    if not runs or #runs == 0 or cap < 1 then return nil end
    unit = unit or "player"
    filter = filter or "HELPFUL"
    local c = LAC:CreateContainer("CUE_SR_BorderTap_" .. key, parent)
    c:SetUnit(unit)
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    local set = { container = c, cap = cap, runs = runs, edges = {} }
    -- Two long edges per run, plus one short edge capping each end of the strip. The
    -- caps belong to the first and last run, so they arrive with the stretch they sit
    -- against and the whole thing closes into a rectangle rather than floating lines.
    local function addEdge(runIndex, kind)
        local run = runs[runIndex]
        local col = run.color
        local edge = { runIndex = runIndex, kind = kind }
        edge.button = c:AddAuraSlot(key .. "e" .. (#set.edges + 1), filter, {
            candidateFilters = { includeSpellIDs = spellIDMap },
            initializeFrame = function(btn)
                -- PRE-BIND: creation and styling only. Anchors come after the return,
                -- exactly as in ensurePips (SetPoint errors in this context).
                local clip = CreateFrame("Frame", nil, btn)
                local bar = CreateFrame("StatusBar", nil, clip)
                bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local tex = bar:GetStatusBarTexture()
                if tex then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                    -- Additive is safe here BECAUSE the runs do not overlap: the only
                    -- thing behind an edge is the bar background.
                    tex:SetBlendMode("ADD")
                end
                bar:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
                btn:SetApplicationBar(bar, { maxApplications = cap })
                edge.clip = clip
                edge.bar = bar
            end,
        })
        set.edges[#set.edges + 1] = edge
    end
    for m = 1, #runs do
        addEdge(m, "long1")
        addEdge(m, "long2")
    end
    addEdge(1, "capStart")
    addEdge(#runs, "capEnd")
    for i = 1, #set.edges do
        local clip = set.edges[i].clip
        if clip then clip:SetClipsChildren(true) end
    end
    -- ONE animation for the whole border. It lives on the container, which is an
    -- addon-owned frame, and the engine drives it from there -- no per-frame addon
    -- write, and nothing to read. An edge still shows only where its fill reaches, so
    -- the pulse is invisible until a threshold is actually met.
    local ag = c:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.55)
    set.pulse = ag
    ag:Play()
    auraTap.borderSets[key] = set
    return set
end

---Positions a threshold border over `host` (the whole strip). Every write here is
---blocked while auras are secret, so callers re-invoke from their layout path and the
---first writable pass converges — same contract as layoutPips.
---
---`host` is the ONE cross-frame edge per edge-slot, and a live anchor, so the border
---tracks the strip's resizes with no further writes. Run boundaries are in pip units and
---scaled by the strip's length here rather than stored, so a resize needs no rebuild.
---
---**The border sits OUTSIDE the bar**, offset by its own thickness on every side, so it
---frames the strip rather than covering its first two pixels of fill. The end caps sit at
---the BORDER's extent, not the bar's — with runs ending at the top threshold rather than
---at the cap, those are different places.
---**Boundaries follow the SEGMENTS, not an even division of the strip.** `layoutBars`
---spaces segments at a pitch of `segLen + gap`, so dividing the strip by `cap` puts the
---border's edges further off with every segment and ends a run mid-segment. `segCount`
---distinguishes the two shapes the strip can take: one segment per stack (where a run
---boundary is a real segment edge) versus the single continuous bar `stack_strip_segmented`
---off produces (where it is a fraction of the length).
---@param key string
---@param host frame?  the strip's full rect
---@param vertical boolean
---@param pipW number  one segment's width, as layoutBars sized it
---@param pipH number  one segment's height, as layoutBars sized it
---@param gap number  pixel gap between adjacent segments
---@param segCount integer  rendered segments: `cap` when segmented, 1 when continuous
auraTap.layoutBorder = function(key, host, vertical, pipW, pipH, gap, segCount)
    local set = auraTap.borderSets[key]
    if not set or not host or InCombatLockdown() or auraTap.blocked() then return end
    if not pipW or not pipH or pipW <= 0 or pipH <= 0 then return end
    set.container:SetFrameLevel(host:GetFrameLevel() + 10)
    local t = BORDER_THICKNESS
    local segmented = (segCount or 1) > 1
    -- Every dimension comes from the numbers layoutBars used to size the SEGMENTS, never
    -- from the row frame's own rect. The two can disagree — a row frame is two-point
    -- anchored, so its height reads stale in the same frame (`.context/patterns.md`) —
    -- and when they did, the bottom edge landed inside the bar instead of under it.
    local segLen = vertical and pipH or pipW
    local crossLen = vertical and pipW or pipH
    local pitch = segLen + (gap or 0)
    local stripLen = segmented and ((segCount - 1) * pitch + segLen) or segLen
    ---Where boundary `v` (in pip units, 0..cap) falls along the strip. A leading edge is
    ---the LEFT side of segment v+1; a trailing edge is the RIGHT side of segment v, which
    ---is a gap-width earlier — that difference is the whole point of this helper.
    local function edgeAt(v, trailing)
        if not segmented then return (v / set.cap) * stripLen end
        if trailing then return (v - 1) * pitch + segLen end
        return v * pitch
    end
    -- A cap spans the strip's short dimension plus both long edges, so the corners close.
    local capSpan = crossLen + 2 * t
    for i = 1, #set.edges do
        local edge = set.edges[i]
        local run = set.runs[edge.runIndex]
        local btn, clip, bar = edge.button, edge.clip, edge.bar
        if not (btn and clip and bar and run) then return end
        local isCap = edge.kind == "capStart" or edge.kind == "capEnd"
        local runStart, runStop = edgeAt(run.start, false), edgeAt(run.stop, true)
        local runLen = runStop - runStart
        if runLen <= 0 then return end
        -- A cap is pinned to the end of the run that owns it: capStart to the first run's
        -- start, capEnd to the last run's stop.
        local along = (edge.kind == "capEnd") and runStop or runStart
        btn:ClearAllPoints()
        clip:ClearAllPoints()
        bar:ClearAllPoints()
        -- The edge's own rect, and whether its fill runs along the strip or across it.
        -- A cap always fills across, because it spans the strip's short dimension.
        local bw, bh, fillsVertically
        if vertical then
            -- The strip fills bottom→top, so runs stack vertically and the long edges
            -- are the left and right sides.
            if isCap then
                bw, bh, fillsVertically = capSpan, t, false
                btn:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -t,
                    edge.kind == "capStart" and (along - t) or along)
            else
                bw, bh, fillsVertically = t, runLen, true
                btn:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT",
                    edge.kind == "long1" and -t or crossLen, along)
            end
        else
            if isCap then
                bw, bh, fillsVertically = t, capSpan, true
                btn:SetPoint("TOPLEFT", host, "TOPLEFT",
                    edge.kind == "capStart" and (along - t) or along, t)
            else
                bw, bh, fillsVertically = runLen, t, false
                btn:SetPoint("TOPLEFT", host, "TOPLEFT", along,
                    edge.kind == "long1" and t or -crossLen)
            end
        end
        btn:SetSize(bw, bh)
        clip:SetAllPoints(btn)
        -- The window length along the FILL axis is what the reveal scales against, so it
        -- is read off the rect rather than restated — a cap fills across the strip, a long
        -- edge along its run.
        local windowLen = fillsVertically and bh or bw
        local back = (run.value - 1) * windowLen
        -- The bar is `cap` windows long inside the clip and slid back by the threshold,
        -- so its own slice lands in the window exactly when the stack count reaches it.
        bar:SetOrientation(fillsVertically and "VERTICAL" or "HORIZONTAL")
        if fillsVertically then
            bar:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, -back)
            bar:SetSize(bw, windowLen * set.cap)
        else
            bar:SetPoint("TOPLEFT", clip, "TOPLEFT", -back, 0)
            bar:SetSize(windowLen * set.cap, bh)
        end
    end
end

---Shows or hides a threshold border. The container is a plain addon frame, so this is
---ungated — the bound bars follow it.
---@param key string
---@param shown boolean
auraTap.setBorderShown = function(key, shown)
    local set = auraTap.borderSets[key]
    if set then set.container:SetShown(shown) end
end

---Creates (once) a dedicated AuraContainer + slot whose button carries a plain
---BackdropTemplate border child covering `target`. NOTHING IS BOUND: the engine
---Show/Hides the slot button per aura presence (ApplyVisibility does
---SetShown(secretwrap(auraData ~= nil))), and an UNBOUND child frame renders
---exactly while the button is shown — so the border tracks the aura with zero
---addon reads and keeps working while auras are secret. Same shape as
---ebonMightTap.glow (Components/PrimaryResources.lua), live-verified.
---Border only, no bgFile: the tap renders at its own container's strata, above
---the target's fill and text, so a filled overlay would mask them.
---button:SetAllPoints(target) is the ONE cross-frame edge and a LIVE anchor —
---it tracks target resizes with no further writes; the border is in-family.
---Colour is the only mutable part and converges on every call. Creation is a
---no-op in combat and while auras are secret; callers re-invoke from their
---update path, so the first writable tick builds it.
---@param slotKey string
---@param spellIDMap table<number, boolean>
---@param target Frame
---@param color number[]
auraTap.ensureGlow = function(slotKey, spellIDMap, target, color)
    local glow = auraTap.glows[slotKey]
    if glow then
        if not auraTap.blocked() then
            glow:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
        end
        return
    end
    if not target or InCombatLockdown() or auraTap.blocked() then return end
    local c = LAC:CreateContainer("CUE_SR_AuraTapGlow_" .. slotKey, target)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    local button = c:AddAuraSlot(slotKey, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spellIDMap },
    })
    -- Post-return: SetPoint/SetBackdrop inside initializeFrame error under
    -- UntrustedLayoutScriptExecution.
    button:SetAllPoints(target)
    glow = CreateFrame("Frame", nil, button, "BackdropTemplate")
    glow:SetAllPoints(button)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    glow:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    auraTap.glowContainers[slotKey] = c
    auraTap.glows[slotKey] = glow
end

---Same container/slot shape as ensureGlow, but the border is handed to the
---engine through `button:AddPandemicRegion(host)` instead of tracking the aura's
---mere presence: Blizzard then SetShows it only inside the refresh-carryover
---window, which is the one "running out" cue that survives aura secrecy.
---
---Two rules from .context/patterns-auracontainer.md "Pandemic regions" shape
---this. The registered object is the HOST and the art is drawn ON it (the
---backdrop's border is a region of the host, not a child frame): AddPandemicRegion
---stamps Enum.SecretAspect.Shown on whatever it is given, so anything nested
---inside would put a second, unreadable shown state between the engine's
---decision and the pixels. And the host must be a DESCENDANT of the button,
---which is also what gives it the button's own aura-driven hide for free.
---Registration is last so the stamp lands after our writes.
---
---⚠️ **Expected to stay dark for a buff nothing refreshes.** Blizzard derives the
---window from `GetRefreshExtendedDuration - GetAuraBaseDuration`; a buff that is
---applied once and never refreshed has no carry-over, so the difference is 0 and
---no window ever opens. Kept behind an opt-in setting for exactly that reason —
---see Components/SecondaryResources.md "Devastation Evoker — Unbound Flame".
---@param slotKey string
---@param spellIDMap table<number, boolean>
---@param target Frame
---@param color number[]
auraTap.ensurePandemic = function(slotKey, spellIDMap, target, color)
    local host = auraTap.pandemics[slotKey]
    if host then
        if not auraTap.blocked() then
            host:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
        end
        return
    end
    if not target or InCombatLockdown() or auraTap.blocked() then return end
    local c = LAC:CreateContainer("CUE_SR_AuraTapPandemic_" .. slotKey, target)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    local button = c:AddAuraSlot(slotKey, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spellIDMap },
    })
    -- Post-return, same as ensureGlow: SetPoint/SetBackdrop inside
    -- initializeFrame error under UntrustedLayoutScriptExecution.
    button:SetAllPoints(target)
    host = CreateFrame("Frame", nil, button, "BackdropTemplate")
    host:SetAllPoints(button)
    host:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    host:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    button:AddPandemicRegion(host)
    auraTap.glowContainers[slotKey] = c
    auraTap.pandemics[slotKey] = host
end

---Addon-side gate for a glow tap (setting off, wrong spec, wrong power type).
---The container is a plain addon frame, so this is safe in combat; the BUTTON's
---own Show/Hide stays the engine's, which is what carries the aura state.
---Also gates a pandemic tap: the host's own shown state stops being ours the
---moment AddPandemicRegion stamps it, so container-level is the only gate left.
---@param slotKey string
---@param enabled boolean
auraTap.setGlowEnabled = function(slotKey, enabled)
    local c = auraTap.glowContainers[slotKey]
    if c then c:SetShown(enabled) end
end

---Re-point an existing tap slot at a different spell set.
---
---`SetAuraSlotCandidateFilters` is a plain Lua mixin method
---(`Blizzard_CustomAuraContainer.lua:434`) — there is no `InCombatLockdown`
---anywhere in `Blizzard_AuraContainer/`, and the combat restriction that does
---exist (`DenyTaintedAccessWhenAurasAreSecret`) is stamped on the slot BUTTON,
---so it governs writes into the button's subtree, not container calls. Callers
---may therefore re-filter freely, in or out of combat.
---
---Callers MUST dedupe, though: every call ends in `UpdateAllAuras()`, a full
---candidate re-evaluation. That is the same reason `Core/AuraContainer.lua`
---guards its slot syncs behind a spell-order signature.
---@param slotKey string
---@param spellIDMap table<number, true>
auraTap.setSlotFilter = function(slotKey, spellIDMap)
    local c = auraTap.glowContainers[slotKey]
    if not c then return end
    c:SetAuraSlotCandidateFilters(slotKey, { includeSpellIDs = spellIDMap })
end

---Same unbound-child contract as ensureGlow — the engine Show/Hides the slot
---button per aura presence and an unbound child renders exactly while the
---button is shown — but a filled ColorTexture rather than a border, so it
---MASKS the target's own fill. That masking is the point: the fill is the
---readout, not a decoration around one.
---
---The gate is deliberately container-level (auraTap.setGlowEnabled) rather
---than a flag on the texture. Blizzard applies
---`ScriptObjectAccessRestriction.DenyTaintedAccessWhenAurasAreSecret` to the
---slot button post-creation (Blizzard_AuraContainerFrameProviders.lua:85) and
---forbidden aspects propagate down parent/child hierarchies, so nothing under
---the button is writable in combat. The container is a plain addon frame and
---is — same reason setGlowEnabled works. Consequence: one gate needs one
---container, so a per-slot gate needs one container PER SLOT.
---
---Uses a Texture, not a BackdropTemplate frame: cheaper, and it sidesteps the
---"no SetBackdrop in a button's subtree" rule in patterns-auracontainer.md
---outright rather than relying on the slot button's rect being addon-derived.
---button:SetAllPoints(target) is the ONE cross-frame edge and a LIVE anchor.
---Creation is a no-op in combat and while auras are secret; callers re-invoke
---from their update path, so the first writable tick builds it.
---@param slotKey string
---@param spellIDMap table<number, boolean>
---@param target Frame
---@param color number[]
auraTap.ensureFill = function(slotKey, spellIDMap, target, color)
    local fill = auraTap.fills[slotKey]
    if fill then
        if not auraTap.blocked() then
            fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
        return
    end
    if not target or InCombatLockdown() or auraTap.blocked() then return end
    local c = LAC:CreateContainer("CUE_SR_AuraTapFill_" .. slotKey, target)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    -- Above the bar fill (+0) and predictionBar (+1), below the essencePred
    -- border (+3) and the configurable bar border (+5) — the two overlays
    -- cover the same slots whenever EB is up, and the border reads on top.
    c:SetFrameLevel(target:GetFrameLevel() + 2)
    c:SetEnabled(true)
    c:Show()
    local button = c:AddAuraSlot(slotKey, "HELPFUL", {
        candidateFilters = { includeSpellIDs = spellIDMap },
    })
    -- Post-return: SetPoint inside initializeFrame errors under
    -- UntrustedLayoutScriptExecution.
    button:SetAllPoints(target)
    fill = button:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(button)
    fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    auraTap.glowContainers[slotKey] = c
    auraTap.fills[slotKey] = fill
end

-- ── Skyriding Vigor state ──────────────────────────────────────────────────

---Skyriding vigor recharge state. Fields: startTime (GetTime() when the
---current charge began recharging), fillDuration (seconds to recharge one
---charge at the current rate), charges (whole vigor charges from the last
---update), isThrill (true while Thrill of the Skies is active for fast regen).
---@type table
local vigorState = { charges = 0, isThrill = false }

-- ── Discipline Priest Radiance charge state ─────────────────────────────────

---Mirrors the Fire Blast / Aimed Shot pattern: the secret currentCharges value
---is cached here only to be piped straight into AllowedWhenTainted methods
---(SetValue / SetText / EvaluateColorFromBoolean). No addon-side arithmetic —
---segment fills come from offset MinMax + SetValue, and the in-progress fill
---comes from a single recharge overlay driven by SetTimerDuration.
local cachedRadianceCharges = 0
local cachedRadianceMax = 0

-- ── Fury Warrior Whirlwind charge state ──────────────────────────────────────

---Holds all WW charge-tracking state in one table to stay within the file's
---200-local cap. Fields:
---  charges (0–4 current charges), expiresAt (GetTime when charges expire, nil
---  if none), lastCastGUID (dedup for UNIT_SPELLCAST_SUCCEEDED),
---  noConsumeUntil (timestamp blocking Bloodthirst/Bloodbath consumption during
---  Unhinged + Bladestorm), eventFrame (UNIT_SPELLCAST_SUCCEEDED listener),
---  updateChargeDisplay (writes charges to bars), onUpdate (expiry tick).
---@type table
local wwState = {
    charges = 0,
    noConsumeUntil = 0,
}

-- ── Survival Hunter Tip of the Spear state ──────────────────────────────────

---Survival Hunter Tip of the Spear state. Fields: charges (0–3 stacks),
---eventFrame (UNIT_AURA listener), updateChargeDisplay (forward-declared bar
---writer; assigned after helpers are in scope).
---@type table
local totsState = { charges = 0 }

-- ── Frost Mage Icicles state ──────────────────────────────────────────────
-- Packed into a single table to conserve file-level local slots (Lua 5.1 200-local limit).

---@class icicles_state
---@field count integer Current stack count (0–5)
---@field durationObj LuaDurationObject? Reusable duration object for the in-progress bar
---@field eventFrame Frame? UNIT_AURA event frame
---@field glowFrame frame? BackdropTemplate pulsing border for full stacks
---@field glowing boolean True when glow animation is playing
---@field updateDisplay fun()? Forward-declared display update function
---@field lastHastedDuration number? Observed Icicle generation interval in seconds; nil until first sample or after a haste-shift wipe
---@field lastStackGainTime number? GetTime() of the last clean stack gain; nil when the next sample has no valid anchor
local iciclesState = { count = -1, glowing = false }

---Returns the current Icicle generation duration in seconds.
---UnitSpellHaste is a secret value in 12.0+ and cannot be divided into a
---base duration, so the realized interval is observed from stack gains
---and cached. Falls back to the unhasted base (combat-halved, Hailstones-
---adjusted) until the first sample is recorded after a wipe.
iciclesState.getHastedDuration = function()
    if iciclesState.lastHastedDuration then
        return iciclesState.lastHastedDuration
    end
    local base = SRC.ICICLES_BASE_DURATION
    if not InCombatLockdown() then
        base = base / 2
    end
    if IsPlayerSpell(SRC.HAILSTONES_TALENT_ID) then
        base = base - 1
    end
    return base
end

-- ── Guardian Druid Ironfur state ─────────────────────────────────────────────
-- Packed into a single table (Lua 5.1 200-local limit). Tracks individual Ironfur
-- casts via UNIT_SPELLCAST_SUCCEEDED; aura is secret so no aura API reads.

---@class ironfur_instance
---@field expiresAt number  GetTime() + computed duration at cast time
---@field duration  number  actual duration of this cast (base + talent bonuses)

---@class ironfur_state
---@field instances ironfur_instance[] active instances, ordered oldest-first
---@field durationObj LuaDurationObject? reusable duration object for SetTimerDuration
---@field ticks texture[] pool of tick mark textures (grows dynamically)
---@field eventFrame Frame?
---@field lastCount integer previous instance count for change detection
---@field ursocKnown boolean Ursoc's Endurance talented (+2s all casts)
---@field goeKnown boolean Guardian of Elune talented
---@field goeActive boolean GoE buff is up (next IF gets +3s)
local ironfurState = { instances = {}, ticks = {}, lastCount = 0, ursocKnown = false, goeKnown = false, goeActive = false }

-- ── Enhancement Shaman Maelstrom Weapon state ───────────────────────────────

---Enhancement Shaman Maelstrom Weapon state. Fields: charges (0 to the
---variant's max), variant (the `SRC.mwVariants` entry the aura read and the
---segment count use; set when the events register, which each Refresh does
---before it lays out or reads), eventFrame (UNIT_AURA listener),
---updateChargeDisplay (forward-declared bar writer; assigned after helpers are
---in scope).
---@type table
local mwState = { charges = 0, variant = SRC.mwVariants[1] }

-- ── Rogue Coup de Grâce (Trickster) state ───────────────────────────────────

---Rogue Coup de Grâce / Escalating Blade state. The stack count is never read:
---four slot-bound StatusBars render it engine-side (`auraTap.ensurePips` under
---the "cdg" key). Fields: pips (the plain frames marking each strip's rect —
---geometry hosts only, they draw nothing), updateDisplay/layoutPips
---(forward-declared, assigned after helpers are in scope).
---@type table
local cdgState = { pips = {} }

---Current active secondary power type (one of the SRC.* constants). Forward-declared
---here so functions defined above its initial assignment (e.g. layoutStaggerPips)
---can capture it as an upvalue.
---@type string?
local playerPowerType

-- ── Monk Vitality (Aspect of Harmony) state ─────────────────────────────────

---Event frame for Vitality tracking via UNIT_AURA.
---@type Frame?
local vitalityEventFrame

---Forward declaration for Vitality display update (body assigned after helpers are in scope).
---@type fun()
local updateVitalityBar

---Protection Warrior Ignore Pain state. Fields: updateBar/syncPandemic/
---ensureTap/applyTapFont (forward-declared, assigned after helpers are in
---scope), tapContainer/tapButton/tapBar/tapText (the engine-driven aura-tap
---readout; nil until the first writable pass builds it), tapTimeMode (the
---display mode baked into the current bind), and pandemicHost/pandemicBorder/
---pandemicKey (the native `AddPandemicRegion` carrier on the tap button, its
---styled child, and the `RemovePandemicRegion` argument while registered).
---No CDM state: the readout and the pandemic cue are both engine-driven.
---@type table
local ipState = {}

---Arms Warrior Sweeping Strikes state. The stack count is never read — the
---strip is engine-driven (`auraTap.ensurePips` under the "sweepingstrikes"
---key), so all that is left here is the cap resolver.
---Fields: getMaxStacks (forward-declared, body assigned later — 12 base, 18
---with Improved Sweeping Strikes).
---
---A `maxStacks` field was mirrored here on every render until the STACK_STRIPS
---rework. Nothing read it but the line that had just written it, so the strip's
---`cap` now calls `getMaxStacks` directly.
---@type table
local ssState = {}

---Shared state for the eight engine-driven stack strips (Sweeping Strikes,
---Teachings of the Monastery, Shatter, Wild Imps, Arcane Salvo, Unbound Flame,
---nearby Soul Fragments, Art of the Glaive) — see `STACK_STRIPS`, which
---describes them all.
---Each renders one
---secret `applications` count as N discrete pips -- or, with `stack_strip_segmented`
---off, one continuous bar -- so they share one implementation. `text` and
---`fontDirty` are a single shared instance, which is why the numeric readout is
---player-unit strips only and why two of them cannot carry one at once (Art of
---the Glaive opts out via its `noReadout` row for exactly that reason; Unbound
---Flame opts out because the number was wrong and unwanted); the
---last six are extra rows and CAN be on screen alongside another resource.
---Fields: text (the bound FontString that
---replaces the addon-owned valueText), fontDirty (a font write arrived while
---auras were secret; the next writable pass re-applies it), segmentsFor
---(forward-declared, body assigned later — the cap → rendered-segment-count
---mapping every stack strip shares), arcaneSalvoMax (Arcane Salvo's
---talent-scaled cap) and nearbySoulsMax (the DH strip's spec-scaled cap);
---neither of those two owns a state table of its own.
---@type table
local stackTap = {}

-- ── Fire Mage Fire Blast charge state ────────────────────────────────────────

---Cached Fire Blast charge count from last update.
---@type integer
local cachedFireBlastCharges = 0

---Cached Fire Blast max charges from last update.
---@type integer
local cachedFireBlastMax = 2

-- ── Marksmanship Hunter Aimed Shot charge state ─────────────────────────────

---Cached Aimed Shot charge count from last update.
---@type integer
local cachedAimedShotCharges = 0

---Cached Aimed Shot max charges from last update.
---@type integer
local cachedAimedShotMax = 2

---Returns the max Fire Blast charges based on whether Flame On is known.
---@return integer
local function getFireBlastMaxCharges()
    return IsPlayerSpell(SRC.FLAME_ON_SPELL_ID) and 3 or 2
end

-- ── Paladin Crusading Strikes swing timer state ─────────────────────────────

---Cached mainhand weapon base swing speed in seconds, parsed from the
---tooltip via C_TooltipInfo.GetInventoryItem at register time and on
---PLAYER_EQUIPMENT_CHANGED / PLAYER_ENTERING_WORLD. Updated only on a
---successful parse; a failed read preserves the prior value.
---nil until the first good read.
---Stored on `private` to avoid the file's 200-local limit.
---@type number?
private.cachedMainhandSpeed = nil

---Current haste multiplier sampled from Redemption's cast time
---(spellID 7328 — fixed 10s base across all paladin specs, scales linearly with
---haste). Formula: hasteMult = 10000 / castTime. Realized swing duration for
---OnUpdate is cachedMainhandSpeed × CRUSADING_STRIKES_PERIOD_FACTOR / swingHasteMult.
---Stored on `private` to avoid the file's 200-local limit.
---@type number?
private.swingHasteMult = nil

---Debounce flag for haste sampling. Set by events that might have changed
---haste (UNIT_AURA, SPELL_UPDATE_COOLDOWN); consumed and cleared at the top
---of the OnUpdate handlers so many fires per frame collapse into one sample.
---Stored on `private` to avoid the file's 200-local limit.
---@type boolean
private.swingHasteDirty = true

---Cached (configID → nodeID) lookup for Zealot's Fervor so we walk the class
---tree at most once per loadout. Mirrors the Innate Magic resolved cache.
---Stored on `private` to avoid the file's 200-local limit.
---@type { configID: number?, nodeID: number? }
private.zealotsFervorResolved = private.zealotsFervorResolved or { configID = nil, nodeID = nil }

---Cached Zealot's Fervor speed multiplier (1.0 untalented, 1.20 rank 1,
---1.40 rank 2). Read every OnUpdate frame inside the swing-duration formula,
---so we cache the resolved number rather than calling C_Traits.GetNodeInfo
---per frame (NodeInfo allocates a table — bad for the per-frame allocation
---budget). Refreshed at swingState.registerEvents() time, which is itself
---re-run on every PLAYER_TALENT_UPDATE via the Refresh chain.
---Stored on `private` to avoid the file's 200-local limit.
---@type number
private.swingZealotsFervorMult = 1.0

---Crusading Strikes swing-timer state. Fields: startTime (GetTime() when the
---last swing landed), eventFrame (UNIT_SPELLCAST_SUCCEEDED listener), fillIndex
---(resource frame index currently showing the swing fill = currentHP + 1),
---refreshHasteMult/refreshMainhandSpeed/refreshZealotsFervorMult/updateBars/
---registerEvents/unregisterEvents (forward-declared, assigned after helpers
---are in scope), overflowBorder (BackdropTemplate frame for the overflow
---glow; nil until created), overflowGlowing (true while the LCG glow is active).
---@type table
local swingState = { overflowGlowing = false }

-- ── Warlock Spend Prediction state ──────────────────────────────────────────

---Warlock spend-prediction state. Fields: cost (Soul Shard segments the
---current cast will spend; 0 = no prediction active), eventFrame (dedicated
---spellcast-event listener), apply/clear/registerEvents/unregisterEvents
---(forward-declared, assigned after helpers are in scope).
---@type table
local spendPredState = { cost = 0 }

---Forward declaration; body assigned after getResourceColor and getSettings are available.
---@type fun()
local applyColors

---Forward declarations for resource threshold colors (per-spec segment recoloring).
---Tier A resources use applyThresholdColors (direct count lookup, all 3 modes).
---Tier B (SpellChargeInfo-backed Fire Blast / Aimed Shot) uses applyThresholdColorsSecret
---(EvaluateColorFromBoolean fold, "all" mode only).
---@type fun()
local applyThresholdColors
---@type fun(secretCount: any, baseColorObj: table?)
local applyThresholdColorsSecret
---Tier C (stack strips) uses stackThresholdColor: no count at all, just the pip's own
---index. Declared here because updateStackPips reaches it ~2700 lines above the
---definition, which sits with the other threshold functions.
---@type fun(base: string, i: integer): number?, number?, number?, number?
local stackThresholdColor
---Tier C's other consumer: the animated threshold border slices the strip into one run
---per threshold. Declared alongside its neighbours for the same reason.
---@type fun(base: string, isPrimary: boolean, cap: integer): table[]?
local stackThresholdRuns
---@type fun(base: string): number
local stackThresholdSig
---@type fun(): boolean
local isSecretBackedResource
---@type fun(): integer?
local getCurrentResourceCount

---Forward declaration for the layout tail of the two engine-driven stack strips
---(Sweeping Strikes / Teachings); body assigned alongside updateStackPips.
---@type fun(pipW: number, pipH: number, vertical: boolean)
local layoutStackPips
---Forward declaration; returns the active stack strip's tap key, aura IDs and
---pip count, or nil when the current resource is not one of the two.
---@type fun(): string?, table<number, boolean>?, integer?
local stackPipSpec

---Forward declaration; hides the per-resource overlays that hang off the
---component frame rather than off a row (the three recharge clip frames and the
---Icicles glow), so a released row takes its own with it. Declared here because
---`releaseRow` is defined well above the clip-frame locals it has to reach.
---@type fun(powerType: integer|string|nil)
local hideRowOverlays

---Forward declaration; Frost Mage Shatter state. Declared here because
---`hideRowOverlays` is defined far above the definition site and calls into it —
---a plain `local` there would leave that call reading a nil global.
---@type table
local shatterState

---Every stack strip, keyed by the resource token that selects it.
---
---A stack strip renders one secret aura `applications` count as N discrete pips
---(or, with `stack_strip_segmented` off, one continuous bar). Adding one used to
---mean naming it in **nine** places -- `stackPipSpec`, `refreshResourceCount`'s
---host branches, `releaseRow`, `hideStackPips`, `registerPowerEvents`,
---`isSecretBackedResource`, `refreshRow`, `updateValueText` and the colour
---resolver -- and a miss in any of them failed SILENTLY in a different way:
---missing from the token chain built no strip at all (the Shatter bug), missing
---from a teardown list left it drawing over whatever replaced it (the Arcane
---Salvo bug). Both shipped. One row here now feeds all nine.
---
---Fields:
---  base      row-scoped tap-key base, fed to `tapKeyForRow`
---  auraIDs   spell-ID set the pip tap matches (inline: nothing else reads them)
---  cap       resolved fresh per render, never cached -- talent- and
---            spec-scaled caps move without an event of their own. Uniformly a
---            function even where the answer is constant, so callers need no
---            type test on a path that runs hundreds of times a second.
---  colorKey  profile key for the bar colour
---  unit      aura unit; nil means the player (only Shatter differs)
---  filter    aura filter; nil means the default "HELPFUL"
---  noReadout suppresses the shared bound count FontString (see updateStackPips)
---@type table<string, table>
local STACK_STRIPS = {
    [SRC.SWEEPING_STRIKES_ARMS] = {
        base = "sweepingstrikes",
        labelKey = "STACK_STRIP_NAME_SWEEPING_STRIKES",
        auraIDs = { [SRC.SS_BUFF_SPELL_ID] = true },
        colorKey = "arms_sweeping_strikes_color",
        cap = function() return ssState.getMaxStacks() end,
    },
    [SRC.TEACHINGS_MONK] = {
        base = "teachings",
        labelKey = "STACK_STRIP_NAME_TEACHINGS",
        auraIDs = { [SRC.TOTM_BUFF_SPELL_ID] = true },
        colorKey = "mistweaver_teachings_color",
        cap = function() return SRC.TOTM_MAX_STACKS end,
    },
    [SRC.SHATTER_FREEZING] = {
        base = "shatter",
        labelKey = "STACK_STRIP_NAME_SHATTER",
        auraIDs = { [SRC.FREEZING_AURA_ID] = true },
        colorKey = "mage_shatter_color",
        cap = function() return SRC.FREEZING_MAX_STACKS end,
        -- The only strip bound to a unit other than the player.
        unit = "target",
        filter = "HARMFUL|PLAYER",
    },
    [SRC.WILD_IMPS_DEMO] = {
        base = "wildimps",
        labelKey = "STACK_STRIP_NAME_WILD_IMPS",
        auraIDs = { [SRC.WILD_IMP_AURA_ID] = true },
        colorKey = "warlock_wild_imps_color",
        cap = function() return SRC.WILD_IMP_MAX_STACKS end,
    },
    [SRC.ARCANE_SALVO] = {
        base = "arcanesalvo",
        labelKey = "STACK_STRIP_NAME_ARCANE_SALVO",
        auraIDs = { [SRC.ARCANE_SALVO_AURA_ID] = true },
        colorKey = "mage_arcane_salvo_color",
        cap = function() return stackTap.arcaneSalvoMax() end,
    },
    [SRC.UNBOUND_FLAME] = {
        base = "unboundflame",
        labelKey = "STACK_STRIP_NAME_UNBOUND_FLAME",
        auraIDs = { [SRC.UNBOUND_FLAME_AURA_ID] = true },
        colorKey = "evoker_unbound_flame_color",
        cap = function() return SRC.UNBOUND_FLAME_MAX_STACKS end,
        -- The pips answer "how many casts left" on their own, and the readout
        -- disagreed with them in play — it showed 1 against 4 available casts.
        -- Dropped rather than chased: a number nobody needs is not worth the
        -- second engine binding. See the note below about what that 1 may mean
        -- for the pips themselves.
        noReadout = true,
    },
    [SRC.NEARBY_SOULS_DH] = {
        base = "nearbysouls",
        labelKey = "STACK_STRIP_NAME_NEARBY_SOULS",
        -- One map, both ids — see the SRC.NEARBY_SOULS_* comment block: only one
        -- can be up on a given character, and the cap comes from the spec index
        -- rather than from which of the two matched, so the id → spec split
        -- never has to be right.
        auraIDs = {
            [SRC.NEARBY_SOULS_AURA_ID] = true,
            [SRC.NEARBY_SOULS_VOID_AURA_ID] = true,
        },
        colorKey = "dh_nearby_souls_color",
        cap = function() return stackTap.nearbySoulsMax() end,
    },
    [SRC.ART_OF_GLAIVE] = {
        base = "artofglaive",
        labelKey = "STACK_STRIP_NAME_ART_OF_GLAIVE",
        auraIDs = { [SRC.AOTG_AURA_ID] = true },
        colorKey = "dh_art_of_glaive_color",
        cap = function() return stackTap.artOfGlaiveMax() end,
        noReadout = true,
    },
}

-- ── Builder Prediction state ──────────────────────────────────────────────

---True only for Destruction Warlock; all other specs treat soul shards as whole units.
---Set in buildPred.populate on Refresh and spec change.
local isDestructionWarlock = false

---Holds all builder prediction state in a single table to stay within the 200
---local/upvalue limit. Fields: amount (number), eventFrame (Frame?),
---spells (table<spellID, {amount, powerType}>), apply/clear/register/unregister/populate (functions).
---@type table
local buildPred = {
    amount = 0,
    eventFrame = nil,
    spells = {},
}

-- ─────────────────────────────────────────────────────────────────────────────

---Returns the resource color for the current player class, respecting profile settings.
---When use_class_color is true, uses RAID_CLASS_COLORS; otherwise uses the profile override.
---Uses UnitClass("player") directly to avoid dependency on Initialize() timing.
---@return number r, number g, number b, number a
local function getResourceColor()
    local colors = private.profile.resource_colors
    local _, class = UnitClass("player")
    if colors.use_class_color then
        local classColor = class and RAID_CLASS_COLORS[class]
        if classColor then
            return classColor.r, classColor.g, classColor.b, 1
        end
        return 1, 0.75, 0, 1
    end
    local c = colors.class_colors[class]
    if c then return private.Util.Color(c) end
    return 1, 0.75, 0, 1
end

---@return secondaryresources_profile_main
getSettings = function()
    return private.profile.components[secondaryResources.name]
end

secondaryResources.GetSettings = getSettings

local cachedStaggerPct = 0

---Pip line textures at 30% and 60% thresholds (OVERLAY layer).
---@type Texture[]
local staggerPips = {}

---Background section textures for light/moderate/heavy zones (BACKGROUND layer).
---@type Texture[]
local staggerSections = {}

---All resource frames ever created (pool — frames are shown/hidden, never destroyed).
---@type Frame[]
local resourceFrames = {}

---Returns the stagger bar color based on the cached stagger percentage.
---Heavy >= 60%, Moderate >= 30%, Light < 30%.
---@return number r, number g, number b, number a
local function getStaggerColor()
    local settings = getSettings()
    local c
    if cachedStaggerPct >= 60 then
        c = settings.stagger_color_heavy
    elseif cachedStaggerPct >= 30 then
        c = settings.stagger_color_moderate
    else
        c = settings.stagger_color_light
    end
    return private.Util.Color(c)
end

---Creates the pip and section textures for stagger threshold markers on the given bar.
---Called lazily on first layout when stagger_pips is enabled.
---@param bar StatusBar
local function createStaggerOverlays(bar)
    if staggerPips[1] then return end
    for i = 1, 2 do
        local pip = bar:CreateTexture(nil, "OVERLAY")
        pip:SetColorTexture(1, 1, 1, 0.8)
        pip:SetSnapToPixelGrid(true)
        pip:SetTexelSnappingBias(0)
        pip:Hide()
        staggerPips[i] = pip
    end
    for i = 1, 3 do
        local section = bar:CreateTexture(nil, "BACKGROUND")
        section:SetSnapToPixelGrid(false)
        section:SetTexelSnappingBias(0)
        section:Hide()
        staggerSections[i] = section
    end
end

---Positions pip lines and section backgrounds for the stagger bar.
---Hides everything and restores normal bg when stagger_pips is disabled.
local function layoutStaggerPips()
    if not resourceFrames[1] then return end
    local settings = getSettings()
    local bar = resourceFrames[1].bar

    if not settings.stagger_pips or playerPowerType ~= SRC.STAGGER_BREWMASTER then
        for i = 1, #staggerPips do staggerPips[i]:Hide() end
        for i = 1, #staggerSections do staggerSections[i]:Hide() end
        resourceFrames[1].bg:SetAlpha(1)
        return
    end

    createStaggerOverlays(bar)

    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local settingsW = isVertical and settings.height or settings.width
    local settingsH = isVertical and settings.width or settings.height
    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 then barWidth = settingsW end
    if barHeight <= 0 then barHeight = settingsH end
    local pipWidth = 2
    local thresholds = {0.3, 0.6}
    local colors = {settings.stagger_color_light, settings.stagger_color_moderate, settings.stagger_color_heavy}

    -- Hide the normal single-color background; sections replace it
    resourceFrames[1].bg:SetAlpha(0)

    -- Position pips at 30% and 60%
    for i = 1, 2 do
        local pip = staggerPips[i]
        pip:ClearAllPoints()
        if isVertical then
            local yPos = barHeight * thresholds[i]
            pip:SetPoint("CENTER", bar, "BOTTOM", 0, yPos)
            private.Pixel.SetSize(pip, barWidth, pipWidth)
        else
            local xPos = barWidth * thresholds[i]
            pip:SetPoint("CENTER", bar, "LEFT", xPos, 0)
            private.Pixel.SetSize(pip, pipWidth, barHeight)
        end
        pip:Show()
    end

    -- Position and color the three sections (0→30%, 30%→60%, 60%→100%)
    local sectionBounds = {0, 0.3, 0.6, 1}
    for i = 1, 3 do
        local section = staggerSections[i]
        local c = colors[i]
        section:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.8)
        section:ClearAllPoints()
        if isVertical then
            local bot = barHeight * sectionBounds[i]
            local top = barHeight * sectionBounds[i + 1]
            section:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, bot)
            section:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, bot)
            section:SetHeight(top - bot)
        else
            local left = barWidth * sectionBounds[i]
            local right = barWidth * sectionBounds[i + 1]
            section:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
            section:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", left, 0)
            section:SetWidth(right - left)
        end
        section:Show()
    end
end

---Returns the DK rune color for the current specialization.
---@return number r, number g, number b, number a
local function getDKSpecColor()
    local settings = getSettings()
    local spec = C_SpecializationInfo.GetSpecialization()
    local c
    if spec == 1 then
        c = settings.dk_blood_color
    elseif spec == 2 then
        c = settings.dk_frost_color
    elseif spec == 3 then
        c = settings.dk_unholy_color
    end
    if c then return private.Util.Color(c) end
    return getResourceColor()
end

---Returns a custom resource color for the current power type, or nil if no override exists.
---@return number? r, number? g, number? b, number? a
local function getCustomResourceColor()
    local settings = getSettings()
    if playerPowerType == SRC.FIRE_BLAST_CHARGES then
        local c = settings.fire_blast_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.AIMED_SHOT_CHARGES then
        local c = settings.marksman_aimed_shot_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.RADIANCE_CHARGES then
        local c = settings.discipline_radiance_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.WW_CHARGES_FURY then
        local c = settings.fury_whirlwind_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.TOTS_CHARGES_SURVIVAL then
        local c = settings.survival_tots_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.ICICLES_FROST then
        local c = settings.frost_icicles_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.IRONFUR_GUARDIAN then
        local c = settings.guardian_ironfur_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        local c = settings.enhancement_mw_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        local c = settings.soul_frag_veng_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.SOUL_FRAG_DEVOURER then
        local c = settings.soul_frag_dev_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.IGNORE_PAIN_PROT then
        local c = settings.protection_ignore_pain_color
        return private.Util.Color(c)
    elseif STACK_STRIPS[playerPowerType] then
        -- Every stack strip resolves its bar colour the same way, from the
        -- profile key its STACK_STRIPS row names.
        local c = settings[STACK_STRIPS[playerPowerType].colorKey]
        return private.Util.Color(c)
    elseif playerPowerType == SRC.STAGGER_BREWMASTER then
        return getStaggerColor()
    elseif playerPowerType == SRC.VITALITY_MONK then
        local c = settings.vitality_color
        return private.Util.Color(c)
    elseif playerPowerType == SRC.SKYRIDING_VIGOR then
        if vigorState.isThrill then
            local c = settings.vigor_thrill_color
            return private.Util.Color(c)
        else
            local c = settings.vigor_color
            return private.Util.Color(c)
        end
    elseif playerPowerType == Enum.PowerType.Runes then
        return getDKSpecColor()
    elseif SRC.continuousBarPowers[playerPowerType] then
        -- Relocated caster resources (Maelstrom/Astral Power/Insanity) carry the
        -- per-power color set on the primary bar's override palette, so a custom
        -- power color follows the resource onto the secondary bar. Gated on the
        -- same override_colors toggle; otherwise fall through to the class color.
        local pc = private.profile.primary_resource_colors
        if pc.override_colors then
            local c = pc.power_colors[SRC.powerTypeTokens[playerPowerType]]
            if c then return private.Util.Color(c) end
        end
    end
    return nil
end

---@type frame?
local resourcesFrame

---The shared tap container sits on UIParent (a bound FontString cannot live under
---a frame we hide), so neither resourcesFrame's Hide() nor its layout fade reaches
---the Devourer soul-fragment count bound under it. Mirror both onto the
---container: hooked on resourcesFrame's OnShow/OnHide/SetAlpha, and run when the
---container is created. Alpha, because the bound FontString is write-blocked
---while auras are secret and SetAlpha on the container is not.
auraTap.syncAlpha = function()
    local c = auraTap.container
    if not c then return end
    c:SetAlpha(resourcesFrame and resourcesFrame:IsVisible() and resourcesFrame:GetAlpha() or 0)
end

---Row containers, one per simultaneously-displayed resource, stacked inside
---resourcesFrame. `resourcesFrame` stays the component frame the anchor system
---owns and sizes; a row owns only its own slice of it, so the segment layout
---(`layoutBars`, `createResourceFrame`) measures and parents to `rowFrame`.
---With a single row the row fills the component frame exactly, which is what
---keeps the one-row case byte-identical to the pre-rework layout.
---
---**Not everything a row displays is parented to it.** The aura-tap pip
---containers, the three recharge clip frames and the Icicles glow all hang off
---`resourcesFrame`, so hiding a row does not hide them — `releaseRow` has to
---take them down explicitly, and it is the authority on this. Anything new that
---parents to the component frame rather than the row must be released there
---too.
---@type frame[]
local rowFrames = {}

---The row the module-level pointers currently aim at. Swapped by `withRow`
---around every per-row pass so the existing single-row logic can run once per
---row unchanged, and left aimed at row 1 outside such a pass — the value-text
---writers, the vigor speed readout and the value-font pass all dereference it
---from outside any pass. It is nil only before `CreateSecondaryResources` has
---built row 1.
---@type frame?
local rowFrame

---Per-row state, parallel to `rowFrames`. Each entry owns the segment pool, the
---count and the resource type that the module-level `resourceFrames` /
---`activeResourceCount` / `playerPowerType` point at while that row is the
---active one.
---
---`span` is the cross-axis size `layoutRows` gave the row, published so
---`layoutBars` can size segments without reading a rect that the same pass just
---re-anchored. nil means "the row fills the component frame" (single-row).
---
---`thresholdLit` is the count `applyThresholdColors` last painted a threshold
---at, nil when it painted nothing; a lower count means the paint is stale.
---@type table[]
local rows = {}

---Index of the row the module-level pointers currently aim at. It is 1 outside
---any `withRow` pass, because row 1 IS the module-level view rather than a copy
---of it: every OnUpdate script, option setter and update function that has not
---been routed through `withRow` goes on reading the primary resource's state
---exactly as it did before the rework.
---@type integer
local rowIndex = 1

---Number of rows the last `syncRows` left active. Every per-row loop — the
---Refresh pass, the power-event dispatch, the resize relayout — runs over
---exactly this many rows.
---@type integer
local activeRowCount = 1

---Number of currently active (visible) resource frames, equal to the last UnitPowerMax result.
---@type integer
local activeResourceCount = 0

---Creates the row container at `index` if absent and returns it. Rows are
---children of the component frame; `layoutRows` gives each one its slice.
---A single row fills the component frame outright, which is what keeps the
---one-row case identical to the pre-rework layout.
---
---Each row carries its own centered value text, so several rows can each show
---their own number. The overlay sits at the row's frame level + 6 and the
---FontString at OVERLAY draw layer 7 — the same absolute level the single
---component-frame overlay had, since a row inherits the component's level.
---
---Row 1 ADOPTS the module-level pool, count and power type instead of starting
---empty. The pre-rework code owns those file locals directly and dozens of paths
---still read them outside any `withRow` pass, so row 1 and the module-level view
---have to be the same state, not a copy that can drift from it.
---@param index integer
---@return frame
local ensureRow = function(index)
    local f = rowFrames[index]
    if f then return f end
    f = CreateFrame("Frame", nil, resourcesFrame)
    f:SetFrameLevel(resourcesFrame:GetFrameLevel())
    rowFrames[index] = f

    local textOverlay = CreateFrame("Frame", nil, f)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(f:GetFrameLevel() + 6)
    local valueText = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetDrawLayer("OVERLAY", 7)
    valueText:SetPoint("CENTER", f, "CENTER", 0, 0)
    valueText:SetJustifyH("CENTER")
    valueText:SetTextColor(1, 1, 1, 1)
    f.valueText = valueText

    if index == 1 then
        rows[1] = rows[1] or { frames = resourceFrames, count = activeResourceCount, powerType = playerPowerType }
    else
        rows[index] = rows[index] or { frames = {}, count = 0 }
    end
    return f
end

---Aims the module-level row pointers at row `index`, taking that row's state
---from `row`. Outside a per-row pass they stay on row 1, so the paths that were
---never routed through `withRow` — the OnUpdate scripts, the option setters, the
---anchor system's queries — keep reading the primary resource's state.
---
---The row table is handed in rather than looked up, so this can never decline:
---a presence check here would turn `withRow`'s restore into a silent no-op the
---moment `rows[prevIndex]` went missing, leaving every later pass aimed at the
---wrong row.
---@param index integer
---@param row table
local aimAtRow = function(index, row)
    rowIndex = index
    rowFrame = rowFrames[index]
    resourceFrames = row.frames
    activeResourceCount = row.count
    playerPowerType = row.powerType
end

---Runs `fn` with the module-level row pointers aimed at row `index`, then
---restores them. The per-resource logic reads `resourceFrames`,
---`activeResourceCount`, `playerPowerType` and `rowFrame` as file locals, so
---re-pointing those is what lets the existing single-resource code run once per
---row without touching any of its ~170 call sites.
---
---The count is written back into the row on exit, so a body that changes it
---(`refreshResourceCount` does, on every branch) persists it with no second
---write anywhere. The restore re-aims at whichever row was active on entry —
---row 1 outside any pass — rather than replaying saved scalars, which is what
---keeps the module-level view and row 1 the same state.
---
---@param index integer
---@param fn fun()
local withRow = function(index, fn)
    local row = rows[index]
    if not row or not rowFrames[index] then return end

    local prevIndex = rowIndex
    local prevRow = rows[prevIndex] or row
    -- The live cached type, not the entry row's stamped copy. A row's stamp is
    -- only refreshed by syncRows, so between a transition assigning
    -- playerPowerType and the next syncRows the two disagree -- and re-aiming
    -- would republish the stale stamp. The unguarded OnSizeChanged path reaches
    -- this, and getEnabled() reads playerPowerType, so a stale republish can
    -- flip a resourceless spec back to enabled.
    local prevPowerType = playerPowerType
    aimAtRow(index, row)

    fn()

    row.count = activeResourceCount
    aimAtRow(prevIndex, prevRow)
    playerPowerType = prevPowerType
end

---Row-scoped aura-tap key for `base`. A tap key names a slot set globally — it
---is both the `auraTap.pipSets` index and part of the container's frame name —
---so two rows showing different stack resources would otherwise share one set
---and one strip. Row 1 keeps the bare base string, so the single-row case
---produces exactly the keys and frame names it produced before the rework;
---keys are memoized per (base, row) so the Refresh path allocates nothing.
---@param base string
---@param index integer
---@return string
local tapKeyForRow = function(base, index)
    if index == 1 then return base end
    local perBase = auraTap.rowKeys[base]
    if not perBase then
        perBase = {}
        auraTap.rowKeys[base] = perBase
    end
    local key = perBase[index]
    if not key then
        key = base .. index
        perBase[index] = key
    end
    return key
end

---Cross-axis size in settings space: `height` for the primary row plus
---`extra_row_height` and a gap for each extra. `GetComponentSize` returns it so
---the anchor system sizes the frame to what `layoutRows` is about to draw —
---otherwise adding an extra row would shrink the primary instead of growing the
---component, which is the whole point of giving extras their own height.
---
---Reads `activeRowCount`, the count `syncRows` last published, so the size the
---anchor system sees is the size of the layout that produced it.
---@return number
local crossAxisSpan = function()
    local settings = getSettings()
    local extras = activeRowCount - 1
    if extras < 1 then return settings.height end
    local gap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    return settings.height + extras * ((settings.extra_row_height or settings.height) + gap)
end

---Positions `count` row containers inside the component frame and hides the
---rest. Rows split the cross axis — stacked top-to-bottom for a horizontal
---component, left-to-right for a vertical one — so a row's own segments still
---run along the main axis exactly as they did before.
---
---A single row is anchored to all four sides rather than sized, so it tracks
---the anchor system's live width with no recompute and the one-row case stays
---byte-identical to the pre-rework layout.
---
---**The split is weighted, not even.** Row 1 is the spec's primary and weighs
---`height`; every extra weighs `extra_row_height`. An even split read wrong in
---play — a 4-pip Unbound Flame strip beside 6 Essence segments got the same
---height but fatter segments, so the extra looked like the main bar — and, more
---to the point, it shrank the primary the moment an extra appeared.
---
---Proportional rather than absolute, so the rows always fill the frame exactly:
---the anchor system can drive the cross axis (a left/right-side dependent
---inherits its parent's height), and a literal `SetHeight(settings.height)`
---would overflow or underfill it. When the frame is the size `GetComponentSize`
---asked for — which `crossAxisSpan` derives from the same two settings — row 1
---lands on exactly `height` and each extra on exactly `extra_row_height`.
---@param count integer
local layoutRows = function(count)
    if not resourcesFrame then return end

    for i = count + 1, #rowFrames do
        rowFrames[i]:Hide()
    end
    if count < 1 then return end

    for i = 1, count do
        ensureRow(i):Show()
    end

    if count == 1 then
        rowFrames[1]:ClearAllPoints()
        rowFrames[1]:SetAllPoints(resourcesFrame)
        -- No slice: the row IS the component frame, so layoutBars reads the
        -- component's own cross-axis size rather than a stored split.
        rows[1].span = nil
        return
    end

    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local gap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    local totalGap = gap * (count - 1)
    -- Weights, not sizes — see the note above. Clamped to 1 so a zeroed setting
    -- cannot divide by zero and blank the whole component.
    local primaryWeight = math.max(settings.height, 1)
    local extraWeight = math.max(settings.extra_row_height or settings.height, 1)
    local weightTotal = primaryWeight + (count - 1) * extraWeight

    if isVertical then
        -- Vertical segments run bottom-to-top, so rows sit side by side.
        -- Cold-start fallback only: a two-point-anchored component frame reads
        -- back 0 in the frame its anchors were applied, and the OnSizeChanged
        -- pass re-splits the rows once the real size resolves.
        local frameWidth = resourcesFrame:GetWidth()
        if frameWidth == 0 then
            frameWidth = crossAxisSpan()
        end
        local available = frameWidth - totalGap
        local unit = available * extraWeight / weightTotal
        local primary = available * primaryWeight / weightTotal
        for i = 1, count do
            local f = rowFrames[i]
            local size = i == 1 and primary or unit
            local offset = i == 1 and 0 or (primary + gap + (i - 2) * (unit + gap))
            f:ClearAllPoints()
            private.Pixel.SetPoint(f, "TOPLEFT", resourcesFrame, "TOPLEFT", offset, 0)
            private.Pixel.SetPoint(f, "BOTTOMLEFT", resourcesFrame, "BOTTOMLEFT", offset, 0)
            private.Pixel.SetWidth(f, size)
            rows[i].span = size
        end
    else
        local frameHeight = resourcesFrame:GetHeight()
        if frameHeight == 0 then
            frameHeight = crossAxisSpan()
        end
        local available = frameHeight - totalGap
        local unit = available * extraWeight / weightTotal
        local primary = available * primaryWeight / weightTotal
        for i = 1, count do
            local f = rowFrames[i]
            local size = i == 1 and primary or unit
            local offset = i == 1 and 0 or (primary + gap + (i - 2) * (unit + gap))
            f:ClearAllPoints()
            private.Pixel.SetPoint(f, "TOPLEFT", resourcesFrame, "TOPLEFT", 0, -offset)
            private.Pixel.SetPoint(f, "TOPRIGHT", resourcesFrame, "TOPRIGHT", 0, -offset)
            private.Pixel.SetHeight(f, size)
            rows[i].span = size
        end
    end
end

---Per-row teardown. Runs under `withRow`, so `resourceFrames` / `rowFrame` are
---the leaving row's. The segment pool is never destroyed — the row keeps its
---frames for whatever resource lands there next — but every segment is hidden
---and the count zeroed (which `withRow` writes back) so a row the resolver no
---longer produces cannot leave a stale resource on screen.
---
---The row's pip strips are released too. Their containers are parented to
---`resourcesFrame`, not to the row, so neither hiding the row nor hiding its
---segments takes them with it. They are hidden rather than rebuilt: the tap
---constructors no-op in combat and while auras are secret, so a release that
---tried to reconverge them would leave the strip on screen for exactly the
---pulls it matters. The bases listed below are every row-scoped pip set there
---is — `stackPipSpec` produces all of them but `"cdg"`, which is `cdgState`'s.
---**A new strip must be added here as well as to `hideStackPips`**: the two
---lists cover different paths, and this one is the only thing that reaches a
---strip when a row simply leaves the active set. `tests/stripbases_check.lua`
---enforces it against both lists.
local releaseRow = function()
    for _, rf in ipairs(resourceFrames) do
        rf:Hide()
    end
    activeResourceCount = 0
    if rowFrame.valueText then
        rowFrame.valueText:Hide()
    end
    for _, strip in pairs(STACK_STRIPS) do
        local rowKey = tapKeyForRow(strip.base, rowIndex)
        auraTap.setPipsShown(rowKey, false)
        auraTap.setBorderShown(rowKey, false)
    end
    -- Not a STACK_STRIPS entry: cdgState owns this pip set and drives it
    -- itself, so it is named here and nowhere else.
    auraTap.setPipsShown(tapKeyForRow("cdg", rowIndex), false)
    -- The bound count FontString lives on UIParent, so no frame hide reaches it.
    -- Only the row that owns it may take it down: another row's release must not
    -- blank a readout the owning row is still showing. See stackTap.setShown.
    if stackTap.rowIndex == rowIndex then
        stackTap.rowIndex = nil
        stackTap.setShown(false)
    end
    -- The recharge clip frames and the Icicles glow are singletons parented to
    -- the component frame, so they survive both the row hide and the segment
    -- hide above. They are keyed off the leaving row's own resource rather than
    -- hidden wholesale, so releasing an extra row cannot blank an overlay the
    -- primary is still showing.
    hideRowOverlays(playerPowerType)
end

---Points the row set at `types` (from `getActiveResourceTypes`), positions the
---rows and releases the ones that just left the active set. Every per-row loop
---afterwards runs over `activeRowCount` rows.
---@param types (integer|string)[]
---@param count integer
local syncRows = function(types, count)
    for i = 1, count do
        ensureRow(i)
        -- A row that swaps one resource for another is a transition too, and
        -- Refresh's gate only catches it for the primary -- it compares
        -- types[1]. Without this, an extra row's outgoing resource keeps its
        -- pip strip and overlays on screen while the incoming one draws over
        -- them.
        --
        -- Row 1 DOES reach this, on every primary transition. The transition
        -- paths (ReevaluatePowerType, the talent/spec/shapeshift handlers)
        -- assign playerPowerType and then call Refresh, but rows[1].powerType
        -- is written only here -- so the re-entrant pass still sees the OLD
        -- type in the stamp and the test fires. That is harmless and mildly
        -- useful: withRow aims playerPowerType at the stamped (outgoing) type,
        -- so hideRowOverlays clears the right resource's overlays, and the
        -- loop below rebuilds the row in the same Refresh pass.
        local previous = rows[i].powerType
        if previous ~= nil and previous ~= types[i] then
            withRow(i, releaseRow)
        end
        rows[i].powerType = types[i]
    end
    -- Row geometry only needs re-applying when the row set changed, or when
    -- several rows have to re-split the cross axis. A lone row is anchored to
    -- all four sides of the component frame, so it tracks every resize on its
    -- own — re-anchoring it on every Refresh would be pure churn, and Refresh
    -- runs in combat.
    if count ~= activeRowCount or count > 1 then
        layoutRows(count)
    end
    -- Only the rows that were actually active need releasing. `rowFrames` never
    -- shrinks, so walking it would re-release every row the session has ever
    -- built on every single Refresh — and Refresh runs in combat. Rows above the
    -- previous count were released by the pass that dropped them.
    for i = count + 1, activeRowCount do
        withRow(i, releaseRow)
        rows[i].powerType = nil
    end
    -- The row count is now part of GetComponentSize (crossAxisSpan), so a change
    -- to it resizes the component and anything anchored below it has to move.
    -- Gated on the transition, never fired per Refresh: this is exactly the
    -- "genuine state transition" .context/performance.md allows a relayout for,
    -- and it happens on spec/talent/setting changes, not in the combat loop.
    local rowCountChanged = count ~= activeRowCount
    activeRowCount = count
    if rowCountChanged then
        private.Anchor.OnComponentStateChange()
    end
end

---Cached interpolation mode for SetValue calls on event-driven bars.
---Updated from settings in Refresh; OnUpdate-driven bars (runes, essence, vigor, swing) skip this.
---@type Enum.StatusBarInterpolation
local barInterpolation = Enum.StatusBarInterpolation.ExponentialEaseOut

---Returns false when settings.enabled is false, or when the class has no secondary resource.
local getEnabled = function()
    local settings = getSettings()
    if not settings.enabled then return false end
    if not playerPowerType then return false end
    return true
end

secondaryResources.GetEnabled = getEnabled

---Force the frame visible while skyriding with Vigor so the anchoring system
---shows it regardless of anchor chain visibility (Blizzard hides the
---CooldownViewer while skyriding). Uses GetForceVisible so the user's
---visibility selection is still respected — an explicit Hidden still hides.
---@return boolean
secondaryResources.GetForceVisible = function()
    return isSkyriding and getSettings().skyriding_vigor or false
end

---Lays out the active resource bars horizontally inside resourcesFrame.
---
---**Never reads the row's own rect.** `layoutAllRows` calls `layoutRows` — which
---`ClearAllPoints`es every row and re-anchors it — and then calls this in the
---same pass, so `rowFrame:GetWidth()` reads back 0 and the profile fallback
---sizes the strip for `settings.width` inside a row the anchor system has made
---some other width. Live incident: a zone transition left CooldownTracker 400
---wide, its anchored Essence strip kept 450-wide segments, and only the last
---(two-point-anchored) segment tracked the real edge.
---
---So the main axis comes from `resourcesFrame`, whose rect this pass did not
---touch, and the cross axis from the slice `layoutRows` just computed. Profile
---values stay as the cold-start fallback, for the pass where the component
---frame's own anchors have not resolved yet.
---Only positions the first activeResourceCount frames; hidden extras are untouched.
local layoutBars = function()
    if activeResourceCount == 0 or not rowFrame then return end

    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local settingsW = isVertical and settings.height or settings.width
    local settingsH = isVertical and settings.width or settings.height
    -- nil with a single row: it is anchored to all four sides of the component
    -- frame, so the component's own cross-axis size IS the row's.
    local span = rows[rowIndex] and rows[rowIndex].span
    local frameWidth, frameHeight
    if isVertical then
        frameHeight = resourcesFrame:GetHeight()
        if frameHeight == 0 then
            frameHeight = settingsH
        end
        frameWidth = span or resourcesFrame:GetWidth()
        if frameWidth == 0 then
            frameWidth = settingsW
        end
    else
        frameWidth = resourcesFrame:GetWidth()
        if frameWidth == 0 then
            frameWidth = settingsW
        end
        frameHeight = span or resourcesFrame:GetHeight()
        if frameHeight == 0 then
            frameHeight = settingsH
        end
    end

    local barGap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    local totalGap = barGap * (activeResourceCount - 1)
    local barOrientation = isVertical and "VERTICAL" or "HORIZONTAL"
    -- One segment's size, handed to the pip taps below rather than read back off
    -- the frames: the LAST segment is two-point-anchored, so its GetWidth /
    -- GetHeight is stale in this same frame.
    local pipW, pipH

    if isVertical then
        -- Vertical: segments stack bottom-to-top, each spans full width
        local barHeight = (frameHeight - totalGap) / activeResourceCount
        pipW, pipH = frameWidth, barHeight
        for i = 1, activeResourceCount do
            local resourceFrame = resourceFrames[i]
            resourceFrame:ClearAllPoints()
            resourceFrame.bar:SetOrientation(barOrientation)
            if i == 1 then
                private.Pixel.SetPoint(resourceFrame, "BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, 0)
            else
                private.Pixel.SetPoint(resourceFrame, "BOTTOMLEFT", resourceFrames[i - 1], "TOPLEFT", 0, barGap)
            end
            if i == activeResourceCount then
                private.Pixel.SetPoint(resourceFrame, "BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", 0, 0)
                private.Pixel.SetHeight(resourceFrame, barHeight)
            else
                private.Pixel.SetSize(resourceFrame, frameWidth, barHeight)
            end
        end
    else
        -- Horizontal: segments side-by-side left-to-right
        local barWidth = (frameWidth - totalGap) / activeResourceCount
        pipW, pipH = barWidth, frameHeight
        for i = 1, activeResourceCount do
            local resourceFrame = resourceFrames[i]
            resourceFrame:ClearAllPoints()
            resourceFrame.bar:SetOrientation(barOrientation)
            if i == 1 then
                private.Pixel.SetPoint(resourceFrame, "TOPLEFT", rowFrame, "TOPLEFT", 0, 0)
            else
                private.Pixel.SetPoint(resourceFrame, "TOPLEFT", resourceFrames[i - 1], "TOPRIGHT", barGap, 0)
            end
            if i == activeResourceCount then
                private.Pixel.SetPoint(resourceFrame, "TOPRIGHT", rowFrame, "TOPRIGHT", 0, 0)
                private.Pixel.SetHeight(resourceFrame, frameHeight)
            else
                private.Pixel.SetSize(resourceFrame, barWidth, frameHeight)
            end
        end
    end

    cdgState.layoutPips(pipW, pipH, isVertical)
    layoutStackPips(pipW, pipH, isVertical)
    layoutStaggerPips()
end

---Re-lays out every active row. The component frame's OnSizeChanged handler: a
---resize moves every row's slice, so each row's segments need re-spacing, not
---only the row the module pointers happen to aim at. The single-row case skips
---`layoutRows` entirely — one row is anchored to all four sides of the component
---frame, so it tracks the new size with no recompute and this stays the exact
---`layoutBars` call the handler was before.
local layoutAllRows = function()
    if activeRowCount > 1 then
        layoutRows(activeRowCount)
    end
    for i = 1, activeRowCount do
        withRow(i, layoutBars)
    end
end

---Returns the background color for inactive resource segments.
---When "Use Class Color" is enabled and static background is off, returns 30% of the active class color.
---Otherwise returns the custom background_color from the profile.
---@return number r, number g, number b, number a
local function getBackgroundColor()
    if private.profile.resource_colors.use_class_color then
        local r, g, b, a = getResourceColor()
        return r * 0.3, g * 0.3, b * 0.3, a
    end
    local settings = getSettings()
    local bgColor = settings.background_color
    if bgColor then
        return bgColor[1], bgColor[2], bgColor[3], bgColor[4]
    end
    return 0.2, 0.2, 0.2, 0.8
end

---Applies the profile texture to a resource status bar via LSM lookup.
---If not found or empty, falls back to a solid white fill.
---@param bar StatusBar
---@param texture string LibSharedMedia statusbar key, or "" for default solid fill
local function applyTexture(bar, texture)
    if texture and texture ~= "" then
        local lsmPath = LibSharedMedia:Fetch("statusbar", texture, true)
        if lsmPath then
            bar:SetStatusBarTexture(lsmPath)
            local barTexture = bar:GetStatusBarTexture()
            if barTexture then
                barTexture:SetSnapToPixelGrid(false)
                barTexture:SetTexelSnappingBias(0)
            end
            return
        end
    end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local barTexture = bar:GetStatusBarTexture()
    if barTexture then
        barTexture:SetSnapToPixelGrid(false)
        barTexture:SetTexelSnappingBias(0)
    end
end

---Paints one stack-strip pip: the Tier C threshold colour where a threshold claims it,
---otherwise the strip's flat resource colour.
---
---**Both writers of a pip's appearance must come through here** — the build closure in
---`updateStackPips` and the restyle pass in `applyColors`. A colour baked by one and
---flat-written by the other is invisible, which is exactly how Tier C shipped dead
---(`.context/patterns.md`, the writer-order rule).
---
---The blend mode is pinned rather than left alone: an earlier cut of the glow drew a
---claimed pip additively, and a bar object outliving that setting would otherwise keep
---the ADD it was built with. The animated border replaced that approach — see
---`auraTap.ensureBorder`.
---@param bar StatusBar
---@param pc number[]?  the threshold colour claiming this pip, or nil for the flat colour
---@param texture string  the profile's status bar texture
---@param r number
---@param g number
---@param b number
---@param a number
local function applyPipColor(bar, pc, texture, r, g, b, a)
    applyTexture(bar, texture)
    local barTexture = bar:GetStatusBarTexture()
    if barTexture then
        barTexture:SetBlendMode("BLEND")
    end
    if pc then
        bar:SetStatusBarColor(pc[1], pc[2], pc[3], pc[4] or 1)
    else
        bar:SetStatusBarColor(r, g, b, a)
    end
end

---Creates one new resource frame (background texture + StatusBar) and appends it to the pool.
---Active bar color respects custom resource colors (vigor, stagger, etc.) with class color fallback.
---Background uses 30% of the active color when custom or class colors are active, otherwise profile bg.
---resourceFrame.bar and resourceFrame.bg are stored for access by event handlers.
local createResourceFrame = function()
    local r, g, b, a = getCustomResourceColor()
    local hasCustom = r ~= nil
    if not hasCustom then
        r, g, b, a = getResourceColor()
    end
    local settings = getSettings()
    local bgR, bgG, bgB, bgA
    if settings.use_static_background then
        local c = settings.background_color
        bgR, bgG, bgB, bgA = c[1], c[2], c[3], c[4]
    elseif hasCustom or private.profile.resource_colors.use_class_color then
        bgR, bgG, bgB, bgA = r * 0.3, g * 0.3, b * 0.3, 0.8
    else
        bgR, bgG, bgB, bgA = getBackgroundColor()
    end

    local resourceFrame = CreateFrame("Frame", nil, rowFrame)
    resourceFrame:SetFrameLevel(rowFrame:GetFrameLevel())

    local bg = resourceFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetSnapToPixelGrid(false)
    bg:SetTexelSnappingBias(0)
    bg:SetColorTexture(bgR, bgG, bgB, bgA)
    resourceFrame.bg = bg

    local bar = CreateFrame("StatusBar", nil, resourceFrame)
    bar:SetFrameLevel(resourceFrame:GetFrameLevel())
    bar:SetAllPoints()
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    applyTexture(bar, getSettings().texture)
    bar:SetStatusBarColor(r, g, b, a)
    resourceFrame.bar = bar

    local predBar = CreateFrame("StatusBar", nil, resourceFrame)
    predBar:SetFrameLevel(bar:GetFrameLevel() + 1)
    predBar:SetMinMaxValues(0, 1)
    predBar:SetValue(1)
    applyTexture(predBar, settings.texture)
    predBar:Hide()
    resourceFrame.predictionBar = predBar

    private.Util.ApplyBarBorder(resourceFrame)

    resourceFrames[#resourceFrames + 1] = resourceFrame
end

---Base color mirror for the continuous-bar breakpoint pip host — the fill
---ColorCurve base. Refreshed in refreshResourceCount's continuous branch
---before each Apply (custom override color, else getResourceColor).
local continuousPipBaseColor = {1, 1, 1, 1}

---Breakpoint pip host for the continuous power bar (shared renderer,
---private.BreakpointPips). Created once and mutated in place; bar/key are
---refreshed by refreshResourceCount's continuous branch, and Clear runs at
---the top of every refreshResourceCount pass because resourceFrames are
---pooled across power types.
---@type BreakpointPipHost
local continuousPipHost = {
    bar = nil,
    key = nil,
    unit = "player",
    getPowerType = function() return playerPowerType end,
    isVertical = function() return (getSettings().orientation or "horizontal") == "vertical" end,
    baseColor = continuousPipBaseColor,
}

---Hidden reference StatusBar spanning all Fire Blast segments. Its fill right edge
---auto-positions the recharge overlay bar at the correct segment via secret SetValue.
---@type StatusBar?
local fbRefBar

---Clipping container for the Fire Blast recharge overlay. Sized to the actual segment area
---so the recharge bar is clipped when pushed past the last segment (all charges full).
---@type Frame?
local fbClipFrame

---Single recharge overlay StatusBar for Fire Blast, anchored to fbRefBar's fill texture.
---@type StatusBar?
local fbRechargeBar

---Creates (or updates) the reference bar and recharge overlay for Fire Blast cooldown fill.
---The reference bar spans maxCharges * (segmentSize + barGap) so that at integer charge i,
---its fill edge aligns with segment (i+1)'s start edge. The recharge bar anchors there.
---A clipping container sized to the actual segment area hides the recharge bar when all full.
local function setupFireBlastRechargeBar()
    if activeResourceCount == 0 or not resourcesFrame then return end

    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local barGap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    local segWidth = resourceFrames[1]:GetWidth()
    local segHeight = resourceFrames[1]:GetHeight()

    -- Clipping container spans the actual segment area
    if not fbClipFrame then
        fbClipFrame = CreateFrame("Frame", nil, resourcesFrame)
        fbClipFrame:SetClipsChildren(true)
    end
    fbClipFrame:ClearAllPoints()
    fbClipFrame:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)

    -- Hidden reference bar for positioning via fill edge
    if not fbRefBar then
        fbRefBar = CreateFrame("StatusBar", nil, fbClipFrame)
        fbRefBar:SetAlpha(0)
    end
    fbRefBar:ClearAllPoints()

    if isVertical then
        local refHeight = cachedFireBlastMax * (segHeight + barGap)
        local clipHeight = cachedFireBlastMax * segHeight + (cachedFireBlastMax - 1) * barGap

        fbClipFrame:SetPoint("BOTTOMLEFT", resourceFrames[1], "BOTTOMLEFT", 0, 0)
        fbClipFrame:SetSize(segWidth, clipHeight)

        fbRefBar:SetOrientation("VERTICAL")
        fbRefBar:SetPoint("BOTTOMLEFT", fbClipFrame, "BOTTOMLEFT", 0, 0)
        fbRefBar:SetSize(segWidth, refHeight)
    else
        local refWidth = cachedFireBlastMax * (segWidth + barGap)
        local clipWidth = cachedFireBlastMax * segWidth + (cachedFireBlastMax - 1) * barGap

        fbClipFrame:SetPoint("TOPLEFT", resourceFrames[1], "TOPLEFT", 0, 0)
        fbClipFrame:SetSize(clipWidth, segHeight)

        fbRefBar:SetOrientation("HORIZONTAL")
        fbRefBar:SetPoint("TOPLEFT", fbClipFrame, "TOPLEFT", 0, 0)
        fbRefBar:SetSize(refWidth, segHeight)
    end

    fbRefBar:SetMinMaxValues(0, cachedFireBlastMax)
    fbRefBar:SetValue(cachedFireBlastCharges)
    if not fbRefBar:GetStatusBarTexture() then
        fbRefBar:SetColorFill(1, 1, 1)
    end
    fbClipFrame:Show()

    -- Single recharge bar anchored to fill edge, clipped by container
    if not fbRechargeBar then
        fbRechargeBar = CreateFrame("StatusBar", nil, fbClipFrame)
        fbRechargeBar:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)
    end
    fbRechargeBar:ClearAllPoints()
    if isVertical then
        fbRechargeBar:SetOrientation("VERTICAL")
        fbRechargeBar:SetPoint("BOTTOMLEFT", fbRefBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
        fbRechargeBar:SetSize(segWidth, segHeight)
    else
        fbRechargeBar:SetOrientation("HORIZONTAL")
        fbRechargeBar:SetPoint("TOPLEFT", fbRefBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        fbRechargeBar:SetSize(segWidth, segHeight)
    end
    applyTexture(fbRechargeBar, settings.texture)
    local c = settings.fire_blast_color
    fbRechargeBar:SetStatusBarColor(private.Util.Color(c))
    fbRechargeBar:Hide()
end

---Hidden reference StatusBar spanning all Aimed Shot segments (same pattern as fbRefBar).
---@type StatusBar?
local asRefBar

---Clipping container for the Aimed Shot recharge overlay.
---@type Frame?
local asClipFrame

---Single recharge overlay StatusBar for Aimed Shot, anchored to asRefBar's fill texture.
---@type StatusBar?
local asRechargeBar

---Creates (or updates) the reference bar and recharge overlay for Aimed Shot cooldown fill.
---Clone of setupFireBlastRechargeBar using Aimed Shot state and color.
local function setupAimedShotRechargeBar()
    if activeResourceCount == 0 or not resourcesFrame then return end

    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local barGap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    local segWidth = resourceFrames[1]:GetWidth()
    local segHeight = resourceFrames[1]:GetHeight()

    if not asClipFrame then
        asClipFrame = CreateFrame("Frame", nil, resourcesFrame)
        asClipFrame:SetClipsChildren(true)
    end
    asClipFrame:ClearAllPoints()
    asClipFrame:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)

    if not asRefBar then
        asRefBar = CreateFrame("StatusBar", nil, asClipFrame)
        asRefBar:SetAlpha(0)
    end
    asRefBar:ClearAllPoints()

    if isVertical then
        local refHeight = cachedAimedShotMax * (segHeight + barGap)
        local clipHeight = cachedAimedShotMax * segHeight + (cachedAimedShotMax - 1) * barGap

        asClipFrame:SetPoint("BOTTOMLEFT", resourceFrames[1], "BOTTOMLEFT", 0, 0)
        asClipFrame:SetSize(segWidth, clipHeight)

        asRefBar:SetOrientation("VERTICAL")
        asRefBar:SetPoint("BOTTOMLEFT", asClipFrame, "BOTTOMLEFT", 0, 0)
        asRefBar:SetSize(segWidth, refHeight)
    else
        local refWidth = cachedAimedShotMax * (segWidth + barGap)
        local clipWidth = cachedAimedShotMax * segWidth + (cachedAimedShotMax - 1) * barGap

        asClipFrame:SetPoint("TOPLEFT", resourceFrames[1], "TOPLEFT", 0, 0)
        asClipFrame:SetSize(clipWidth, segHeight)

        asRefBar:SetOrientation("HORIZONTAL")
        asRefBar:SetPoint("TOPLEFT", asClipFrame, "TOPLEFT", 0, 0)
        asRefBar:SetSize(refWidth, segHeight)
    end

    asRefBar:SetMinMaxValues(0, cachedAimedShotMax)
    asRefBar:SetValue(cachedAimedShotCharges)
    if not asRefBar:GetStatusBarTexture() then
        asRefBar:SetColorFill(1, 1, 1)
    end
    asClipFrame:Show()

    if not asRechargeBar then
        asRechargeBar = CreateFrame("StatusBar", nil, asClipFrame)
        asRechargeBar:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)
    end
    asRechargeBar:ClearAllPoints()
    if isVertical then
        asRechargeBar:SetOrientation("VERTICAL")
        asRechargeBar:SetPoint("BOTTOMLEFT", asRefBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
        asRechargeBar:SetSize(segWidth, segHeight)
    else
        asRechargeBar:SetOrientation("HORIZONTAL")
        asRechargeBar:SetPoint("TOPLEFT", asRefBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        asRechargeBar:SetSize(segWidth, segHeight)
    end
    applyTexture(asRechargeBar, settings.texture)
    local c = settings.marksman_aimed_shot_color
    asRechargeBar:SetStatusBarColor(private.Util.Color(c))
    asRechargeBar:Hide()
end

---Hidden reference StatusBar spanning all Radiance segments (same pattern as fbRefBar / asRefBar).
---@type StatusBar?
local radRefBar

---Clipping container for the Radiance recharge overlay.
---@type Frame?
local radClipFrame

---Single recharge overlay StatusBar for Radiance, anchored to radRefBar's fill texture.
---@type StatusBar?
local radRechargeBar

---Hides the overlays that belong to `powerType` but hang off the component
---frame instead of off a row — the three recharge clip frames and the Icicles
---glow. Called from `releaseRow` for the leaving row's own resource only.
---Each is nil until the resource that owns it has been displayed once.
---@param powerType integer|string|nil
hideRowOverlays = function(powerType)
    if powerType == SRC.FIRE_BLAST_CHARGES then
        if fbClipFrame then fbClipFrame:Hide() end
    elseif powerType == SRC.AIMED_SHOT_CHARGES then
        if asClipFrame then asClipFrame:Hide() end
    elseif powerType == SRC.RADIANCE_CHARGES then
        if radClipFrame then radClipFrame:Hide() end
    elseif powerType == SRC.ICICLES_FROST then
        iciclesState.hideGlow()
    elseif powerType == SRC.SHATTER_FREEZING then
        shatterState.unregisterEvents()
        shatterState.tapKey = nil
    end
end

---Creates (or updates) the reference bar and recharge overlay for Power Word: Radiance
---cooldown fill. Clone of setupAimedShotRechargeBar using Radiance state and color.
---Uses the secret-safe SpellChargeInfo pattern: cachedRadianceCharges (secret) flows
---only into AllowedWhenTainted SetValue.
local function setupRadianceRechargeBar()
    if activeResourceCount == 0 or not resourcesFrame then return end

    local settings = getSettings()
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    local barGap = settings.bar_spacing or SRC.DEFAULT_BAR_GAP
    local segWidth = resourceFrames[1]:GetWidth()
    local segHeight = resourceFrames[1]:GetHeight()

    if not radClipFrame then
        radClipFrame = CreateFrame("Frame", nil, resourcesFrame)
        radClipFrame:SetClipsChildren(true)
    end
    radClipFrame:ClearAllPoints()
    radClipFrame:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)

    if not radRefBar then
        radRefBar = CreateFrame("StatusBar", nil, radClipFrame)
        radRefBar:SetAlpha(0)
    end
    radRefBar:ClearAllPoints()

    if isVertical then
        local refHeight = cachedRadianceMax * (segHeight + barGap)
        local clipHeight = cachedRadianceMax * segHeight + (cachedRadianceMax - 1) * barGap

        radClipFrame:SetPoint("BOTTOMLEFT", resourceFrames[1], "BOTTOMLEFT", 0, 0)
        radClipFrame:SetSize(segWidth, clipHeight)

        radRefBar:SetOrientation("VERTICAL")
        radRefBar:SetPoint("BOTTOMLEFT", radClipFrame, "BOTTOMLEFT", 0, 0)
        radRefBar:SetSize(segWidth, refHeight)
    else
        local refWidth = cachedRadianceMax * (segWidth + barGap)
        local clipWidth = cachedRadianceMax * segWidth + (cachedRadianceMax - 1) * barGap

        radClipFrame:SetPoint("TOPLEFT", resourceFrames[1], "TOPLEFT", 0, 0)
        radClipFrame:SetSize(clipWidth, segHeight)

        radRefBar:SetOrientation("HORIZONTAL")
        radRefBar:SetPoint("TOPLEFT", radClipFrame, "TOPLEFT", 0, 0)
        radRefBar:SetSize(refWidth, segHeight)
    end

    radRefBar:SetMinMaxValues(0, cachedRadianceMax)
    radRefBar:SetValue(cachedRadianceCharges)
    if not radRefBar:GetStatusBarTexture() then
        radRefBar:SetColorFill(1, 1, 1)
    end
    radClipFrame:Show()

    if not radRechargeBar then
        radRechargeBar = CreateFrame("StatusBar", nil, radClipFrame)
        radRechargeBar:SetFrameLevel(resourceFrames[1].bar:GetFrameLevel() + 1)
    end
    radRechargeBar:ClearAllPoints()
    if isVertical then
        radRechargeBar:SetOrientation("VERTICAL")
        radRechargeBar:SetPoint("BOTTOMLEFT", radRefBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
        radRechargeBar:SetSize(segWidth, segHeight)
    else
        radRechargeBar:SetOrientation("HORIZONTAL")
        radRechargeBar:SetPoint("TOPLEFT", radRefBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        radRechargeBar:SetSize(segWidth, segHeight)
    end
    applyTexture(radRechargeBar, settings.texture)
    local c = settings.discipline_radiance_color
    radRechargeBar:SetStatusBarColor(private.Util.Color(c))
    radRechargeBar:Hide()
end

---Forward declaration; body assigned after runeState.startTimes/cachedCurrentEssence are in scope.
local updateValueText

---Updates each active resource bar's fill from UnitPower.
---SoulShards use UnitPower(..., true) and UnitPowerDisplayMod for fractional values.
---All other static resources use integer UnitPower; fill is 0 or 1 per slot.
---No-op for Runes and Essence (handled by DurationObject-driven OnUpdate).
local updateResourceValues = function()
    if activeResourceCount == 0 then return end
    if not SRC.staticPowerTypes[playerPowerType] then return end

    local fractionalValue
    if playerPowerType == Enum.PowerType.SoulShards then
        if isDestructionWarlock then
            local shardPower = UnitPower("player", playerPowerType, true)
            local shardModifier = UnitPowerDisplayMod(Enum.PowerType.SoulShards)
            fractionalValue = (shardModifier ~= 0) and (shardPower / shardModifier) or 0
        else
            -- Demonology/Affliction only generate whole shards; skip fragment path to avoid
            -- partial bar fill from in-progress internal fragment counters.
            fractionalValue = UnitPower("player", playerPowerType)
        end
    else
        fractionalValue = SRC.staticPower(playerPowerType)
    end

    for i = 1, activeResourceCount do
        local resourceFrame = resourceFrames[i]
        local fillAmount = math.max(0, math.min(1, fractionalValue - i + 1))
        resourceFrame.bar:SetValue(fillAmount, barInterpolation)
    end

    updateValueText()
    spendPredState.apply()
    buildPred.apply()
    -- Last, as in applyColors: a threshold colour wins over the prediction overlays.
    applyThresholdColors()
end

-- ── Warlock Spend Prediction functions ──────────────────────────────────────

---Applies the prediction color to the top N filled Soul Shard segments that
---will be consumed by the spell currently being cast. No-op unless a cast is
---active and the power type is SoulShards.
spendPredState.apply = function()
    if spendPredState.cost == 0 then return end
    if playerPowerType ~= Enum.PowerType.SoulShards then return end
    if activeResourceCount == 0 then return end

    -- Dim the normal bar color for a "greyed out" look
    local r, g, b = getCustomResourceColor()
    if not r then
        r, g, b = getResourceColor()
    end
    local dim = 0.55
    local predR, predG, predB = r * dim, g * dim, b * dim

    -- Determine current whole shard count (fractional → floor)
    local shardPower = UnitPower("player", Enum.PowerType.SoulShards, true)
    local shardModifier = UnitPowerDisplayMod(Enum.PowerType.SoulShards)
    local currentShards = (shardModifier ~= 0) and math.floor(shardPower / shardModifier) or 0

    -- Dim the top `spendPredState.cost` filled segments (counting down from currentShards)
    local threshold = currentShards - spendPredState.cost
    for i = 1, activeResourceCount do
        if i <= currentShards and i > threshold then
            resourceFrames[i].bar:SetStatusBarColor(predR, predG, predB, 1)
        end
    end
end

---Clears the spend prediction state and restores normal bar colors.
spendPredState.clear = function()
    if spendPredState.cost == 0 then return end
    spendPredState.cost = 0
    applyColors()
end

---Registers spellcast events for Soul Shard spend prediction.
---Creates the event frame on first call; subsequent calls just re-register events.
spendPredState.registerEvents = function()
    if not spendPredState.eventFrame then
        spendPredState.eventFrame = CreateFrame("Frame")
        spendPredState.eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
            if unit ~= "player" then return end

            if event == "UNIT_SPELLCAST_START" then
                local costTable = C_Spell.GetSpellPowerCost(spellID)
                if costTable then
                    for _, entry in ipairs(costTable) do
                        if entry.type == Enum.PowerType.SoulShards then
                            local cost = entry.cost or 0
                            if cost > 0 then
                                spendPredState.cost = cost
                                spendPredState.apply()
                            end
                            return
                        end
                    end
                end
                -- Spell has no shard cost; clear any stale prediction
                spendPredState.clear()
            else
                -- STOP / SUCCEEDED / FAILED / INTERRUPTED
                spendPredState.clear()
            end
        end)
    end
    spendPredState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    spendPredState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    spendPredState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    spendPredState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    spendPredState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
end

---Unregisters spend prediction events and clears state.
spendPredState.unregisterEvents = function()
    if spendPredState.eventFrame then
        spendPredState.eventFrame:UnregisterAllEvents()
    end
    spendPredState.cost = 0
end

-- ── Builder Prediction functions ─────────────────────────────────────────

---Populates buildPred.spells for the player's class. Called in Refresh before
---event registration. Amounts are in raw power units (fragments for Soul Shards
---via UnitPower(..., true), whole units for other power types).
buildPred.populate = function()
    wipe(buildPred.spells)
    local _, class = UnitClass("player")

    if class == "WARLOCK" then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        isDestructionWarlock = (specIndex == 3)
        if specIndex == 3 then -- Destruction
            -- Incinerate: generates ~2 soul shard fragments (0.2 displayed shards)
            buildPred.spells[29722] = { amount = 2, powerType = Enum.PowerType.SoulShards }
            -- Soul Fire: generates 1 full soul shard (10 fragments)
            buildPred.spells[6353] = { amount = 10, powerType = Enum.PowerType.SoulShards }
        elseif specIndex == 2 then -- Demonology
            -- Shadow Bolt: generates 1 full soul shard (10 fragments)
            buildPred.spells[686] = { amount = 10, powerType = Enum.PowerType.SoulShards }
            -- Demonbolt: generates 2 full soul shards (20 fragments) when hardcast
            buildPred.spells[264178] = { amount = 20, powerType = Enum.PowerType.SoulShards }
        end
    elseif class == "MAGE" then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex == 1 then -- Arcane
            -- Arcane Blast: generates 1 Arcane Charge
            buildPred.spells[30451] = { amount = 1, powerType = Enum.PowerType.ArcaneCharges }
        end
    end
end

---Shows prediction overlay bars on the segments that will be filled by the current
---cast. For fractional resources (Soul Shards), sizes the overlay proportionally.
---For whole-unit resources, fills the entire empty segment.
buildPred.apply = function()
    if buildPred.amount == 0 then return end
    if activeResourceCount == 0 then return end
    if not SRC.staticPowerTypes[playerPowerType] then return end

    local settings = getSettings()
    local predColor = settings.builder_prediction_color
    local predR, predG, predB, predA = predColor[1], predColor[2], predColor[3], predColor[4] or 1

    local isVertical = (settings.orientation or "horizontal") == "vertical"

    -- Get current fractional power (same logic as updateResourceValues)
    local currentFractional
    local displayMod = 1
    if playerPowerType == Enum.PowerType.SoulShards then
        displayMod = UnitPowerDisplayMod(Enum.PowerType.SoulShards)
        if isDestructionWarlock then
            local rawPower = UnitPower("player", playerPowerType, true)
            currentFractional = (displayMod ~= 0) and (rawPower / displayMod) or 0
        else
            -- Demonology/Affliction: whole shards only. buildPred.amount is still in
            -- fragments (e.g. 10), so keep displayMod=10 for predictedAmount math.
            currentFractional = UnitPower("player", playerPowerType)
        end
    else
        currentFractional = SRC.staticPower(playerPowerType)
    end

    local predictedAmount = (displayMod ~= 0) and (buildPred.amount / displayMod) or 0
    local predictedTotal = currentFractional + predictedAmount

    for i = 1, activeResourceCount do
        local rf = resourceFrames[i]
        local predBar = rf.predictionBar
        if not predBar then
            -- Frame created before prediction bars were added; skip
            break
        end

        -- Current fill of this segment (0 to 1)
        local segFill = math.max(0, math.min(1, currentFractional - i + 1))
        -- Predicted fill of this segment (0 to 1)
        local segPredFill = math.max(0, math.min(1, predictedTotal - i + 1))
        -- Delta is the overlay portion
        local delta = segPredFill - segFill

        if delta > 0.001 then
            predBar:ClearAllPoints()
            applyTexture(predBar, settings.texture)
            predBar:SetStatusBarColor(predR, predG, predB, predA)

            if isVertical then
                local segHeight = rf:GetHeight()
                predBar:SetOrientation("VERTICAL")
                predBar:SetPoint("BOTTOMLEFT", rf.bar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
                predBar:SetPoint("BOTTOMRIGHT", rf.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                predBar:SetHeight(delta * segHeight)
            else
                local segWidth = rf:GetWidth()
                predBar:SetOrientation("HORIZONTAL")
                predBar:SetPoint("TOPLEFT", rf.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
                predBar:SetPoint("BOTTOMLEFT", rf.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
                predBar:SetWidth(delta * segWidth)
            end
            predBar:SetValue(1)
            predBar:Show()
        else
            predBar:Hide()
        end
    end
end

---Hides all prediction overlay bars and resets builder prediction state.
buildPred.clear = function()
    if buildPred.amount == 0 then return end
    buildPred.amount = 0
    for i = 1, activeResourceCount do
        local rf = resourceFrames[i]
        if rf.predictionBar then
            rf.predictionBar:Hide()
        end
    end
end

---Registers spellcast events for builder prediction.
---Creates the event frame on first call; subsequent calls just re-register events.
buildPred.register = function()
    if not buildPred.eventFrame then
        buildPred.eventFrame = CreateFrame("Frame")
        buildPred.eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
            if unit ~= "player" then return end

            if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
                local entry = buildPred.spells[spellID]
                if entry and entry.powerType == playerPowerType then
                    buildPred.amount = entry.amount
                    buildPred.apply()
                else
                    buildPred.clear()
                end
            else
                -- STOP / SUCCEEDED / FAILED / INTERRUPTED / CHANNEL_STOP
                buildPred.clear()
            end
        end)
    end
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    buildPred.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
end

---Unregisters builder prediction events and clears state.
buildPred.unregister = function()
    if buildPred.eventFrame then
        buildPred.eventFrame:UnregisterAllEvents()
    end
    buildPred.amount = 0
end

---Recolors combo point borders: charged (overloaded) points show a dedicated
---charge-indicator border in `charged_combo_color`, independent of bar_border
---and force-shown while charged. Bar fill is untouched — class/threshold/
---prediction colors own the fill. No-op for non-combo-point power types.
---Overlay frames cached as upvalue `overlays`, keyed by resourceFrame.
local updateComboPointColors
do
local overlays = {}
updateComboPointColors = function()
    if playerPowerType ~= Enum.PowerType.ComboPoints then return end

    local chargedPowerPoints = private.compat.GetUnitChargedPowerPoints("player")
    local c = getSettings().charged_combo_color
    local cr, cg, cb, ca = private.Util.Color(c)
    local thickness = 3

    for i = 1, activeResourceCount do
        local resourceFrame = resourceFrames[i]
        local isCharged = chargedPowerPoints and tContains(chargedPowerPoints, i) or false
        local overlay = overlays[resourceFrame]

        if isCharged then
            if not overlay then
                overlay = CreateFrame("Frame", nil, resourceFrame)
                local edges = {}
                for k = 1, 4 do edges[k] = overlay:CreateTexture(nil, "OVERLAY") end
                edges[1]:SetPoint("TOPLEFT")
                edges[1]:SetPoint("TOPRIGHT")
                private.Pixel.SetHeight(edges[1], thickness)
                edges[2]:SetPoint("BOTTOMLEFT")
                edges[2]:SetPoint("BOTTOMRIGHT")
                private.Pixel.SetHeight(edges[2], thickness)
                edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
                edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
                private.Pixel.SetWidth(edges[3], thickness)
                edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
                edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
                private.Pixel.SetWidth(edges[4], thickness)
                overlay.edges = edges
                overlay:SetFrameLevel(resourceFrame:GetFrameLevel() + 6)
                overlays[resourceFrame] = overlay
            end
            overlay:ClearAllPoints()
            private.Pixel.SetPoint(overlay, "TOPLEFT", resourceFrame, "TOPLEFT", 0, 0)
            private.Pixel.SetPoint(overlay, "BOTTOMRIGHT", resourceFrame, "BOTTOMRIGHT", 0, 0)
            for _, edge in ipairs(overlay.edges) do
                edge:SetColorTexture(cr, cg, cb, ca)
                edge:Show()
            end
            overlay:Show()
        elseif overlay then
            overlay:Hide()
        end
    end

    -- Hide stale charge borders on slots above the active count (spec / talent change).
    for i = activeResourceCount + 1, #resourceFrames do
        local f = resourceFrames[i]
        local overlay = f and overlays[f]
        if overlay then overlay:Hide() end
    end

    applyThresholdColors()
end
end -- do (charge-border overlays scope)

-- ── Rune (DeathKnight) tracking ────────────────────────────────────────────

---DK rune state. Fields: startTimes (per-rune cooldown start GetTime(),
---indexed by visual position; nil = ready), rawDurations (per-rune total
---regen duration in seconds, indexed by visual position; nil = ready),
---displayOrder (sorted mapping from visual position to rune slot index;
---ready runes on the left, regenerating runes on the right sorted by
---remaining time ascending; only populated when sort_runes is enabled),
---remaining (runeSlot → remaining seconds, 0 = ready; reused per call to
---sortDisplayOrder), sortDisplayOrder/refreshValues/onUpdate (functions).
---@type table
local runeState = {
    startTimes = {},
    rawDurations = {},
    displayOrder = {},
    remaining = {},
}

runeState.sortDisplayOrder = function()
    local readyCount = 0
    local regenCount = 0
    local now = GetTime()

    for i = 1, activeResourceCount do
        local start, duration, runeReady = GetRuneCooldown(i)
        if runeReady or not start or start == 0 or not duration or duration == 0 then
            readyCount = readyCount + 1
            -- Write ready runes to the front of runeState.displayOrder directly.
            runeState.displayOrder[readyCount] = i
            runeState.remaining[i] = 0
        else
            runeState.remaining[i] = (start + duration) - now
        end
    end

    -- Collect regenerating rune indices into the tail of runeState.displayOrder,
    -- then sort just that tail slice by remaining time.
    local pos = readyCount
    for i = 1, activeResourceCount do
        if runeState.remaining[i] > 0 then
            pos = pos + 1
            runeState.displayOrder[pos] = i
            regenCount = regenCount + 1
        end
    end
    -- Trim excess from previous calls with more runes.
    for i = pos + 1, #runeState.displayOrder do
        runeState.displayOrder[i] = nil
    end

    -- Sort regenerating portion (indices readyCount+1 .. readyCount+regenCount).
    if regenCount > 1 then
        -- table.sort only works on full arrays; extract, sort, re-insert.
        -- Reuse runeState.remaining's integer keys won't conflict (they're 1..6 rune IDs).
        -- Instead, use a simple insertion sort for <=6 elements — zero allocation.
        for i = readyCount + 2, readyCount + regenCount do
            local val = runeState.displayOrder[i]
            local rem = runeState.remaining[val]
            local j = i - 1
            while j >= readyCount + 1 and runeState.remaining[runeState.displayOrder[j]] > rem do
                runeState.displayOrder[j + 1] = runeState.displayOrder[j]
                j = j - 1
            end
            runeState.displayOrder[j + 1] = val
        end
    end
end

---Reads GetRuneCooldown for each rune slot, optionally sorts by state (ready left,
---regenerating right), caches start/duration by visual position for OnUpdate,
---and sets bar fills immediately.
---Returns true if any rune is still regenerating (caller should keep OnUpdate active).
runeState.refreshValues = function()
    local sortEnabled = getSettings().sort_runes

    if sortEnabled then
        runeState.sortDisplayOrder()
    end

    local hasOnCooldown = false
    local now = GetTime()
    for visualPos = 1, activeResourceCount do
        local runeIndex = sortEnabled and runeState.displayOrder[visualPos] or visualPos
        local start, duration, runeReady = GetRuneCooldown(runeIndex)
        if runeReady or not start or start == 0 or not duration or duration == 0 then
            runeState.startTimes[visualPos] = nil
            runeState.rawDurations[visualPos] = nil
            resourceFrames[visualPos].bar:SetValue(1)
        else
            runeState.startTimes[visualPos] = start
            runeState.rawDurations[visualPos] = duration
            hasOnCooldown = true
            resourceFrames[visualPos].bar:SetValue(math.min(1, (now - start) / duration))
        end
    end
    applyThresholdColors()
    return hasOnCooldown
end

---OnUpdate callback for rune bars. Uses cached start/duration from runeState.refreshValues
---and GetTime() to compute fill fraction — no GetRuneCooldown calls per frame.
---Unregisters when all runes are ready.
runeState.onUpdate = function(self)
    local hasOnCooldown = false
    local readyChanged = false
    local now = GetTime()
    for i = 1, activeResourceCount do
        local start = runeState.startTimes[i]
        if start == nil then
            resourceFrames[i].bar:SetValue(1)
        else
            local dur = runeState.rawDurations[i]
            if not dur or dur == 0 then
                resourceFrames[i].bar:SetValue(1)
            else
                local fraction = (now - start) / dur
                if fraction >= 1 then
                    runeState.startTimes[i] = nil
                    runeState.rawDurations[i] = nil
                    resourceFrames[i].bar:SetValue(1)
                    readyChanged = true
                else
                    resourceFrames[i].bar:SetValue(fraction)
                    hasOnCooldown = true
                end
            end
        end
    end
    if not hasOnCooldown then
        self:SetScript("OnUpdate", nil)
    end
    if readyChanged then
        applyThresholdColors()
    end
    updateValueText()
end

---Forward declaration; assigned in the Essence tracking section below.
---@type integer
local cachedCurrentEssence

-- ── Evoker Essence Burst constants ──────────────────────────────────────────

---Per-spec Essence Burst buff aura spell IDs. Feeds `ebTap.ids` — the candidate
---filter each per-slot aura container is built on, so the engine decides when
---the tint shows. Nothing in this file reads the aura itself.
---@type table<integer, integer>
local ESSENCE_BURST_BUFF = {
    [1] = 359618,  -- Devastation
    [2] = 369299,  -- Preservation
    [3] = 392268,  -- Augmentation
}

---Per-spec representative spender for cost queries (one per spec is enough).
---@type table<integer, integer>
local ESSENCE_BURST_COST_SPELL = {
    [1] = 356995,  -- Disintegrate (Devastation)
    [2] = 364343,  -- Echo (Preservation)
    [3] = 395160,  -- Eruption (Augmentation)
}

---Default (untalented) Essence cost per spec. Used only as a seed when the
---API has not yet reported a real cost (e.g., /reload while EB is already
---active). The live cost is read from C_Spell.GetSpellPowerCost on every
---EB-inactive refresh and reflects talents (Volcanism, etc.), so this seed
---is superseded as soon as EB drops.
---@type table<integer, integer>
local ESSENCE_BURST_BASE_COST = {
    [1] = 3, -- Devastation: Disintegrate/Pyre default cost
    [2] = 2, -- Preservation: Echo default cost
    [3] = 3, -- Augmentation: Eruption default cost (talents reduce to 1–2)
}

-- ── Shared deferred-update infrastructure ──────────────────────────────────
-- Coalesces multiple viewer hook fires per frame into a single refresh call.
-- OnUpdate fires in the same frame's render phase, avoiding next-frame delay.

---@type table<string, boolean>
local deferredDirtyFlags = {}
---@type table<string, function>
local deferredCallbacks = {}
---@type frame?
local deferredFrame

local function deferredOnUpdate(self)
    self:SetScript("OnUpdate", nil)
    for key, dirty in pairs(deferredDirtyFlags) do
        if dirty then
            deferredDirtyFlags[key] = false
            deferredCallbacks[key]()
        end
    end
end

local function markDirty(key)
    if not deferredDirtyFlags[key] then
        deferredDirtyFlags[key] = true
        if not deferredFrame then
            deferredFrame = CreateFrame("Frame")
        end
        deferredFrame:SetScript("OnUpdate", deferredOnUpdate)
    end
end

-- ── Evoker Essence Burst state ─────────────────────────────────────────────

---Display cost (bars to highlight) when Essence Burst is active. Updated live
---from C_Spell.GetSpellPowerCost when EB is inactive; during EB the API returns
---0, so the value is derived from augID.baseCost minus the live ID adjustment.
---nil until the first observation.
---@type integer?
local essenceBurstCost = nil

---Persistent spender-cost prediction overlay on the Essence bar. Highlights the
---N consecutive slots (N = essenceBurstCost) the next spender would consume,
---anchored to the rightmost active (filled or charging) slot and clamped so the
---window never starts below 1. The same window is reused by
---applyEssenceBurstColors so border + burst tint always coincide.
---Methods are stored on the table to conserve file-level local slots.
---@class CUEEssencePred
---@field borders table<frame, frame>
local essencePred = { borders = {} }

---Augmentation Imminent Destruction tracker. Folded into one local to stay
---under Lua 5.1's 200-local chunk limit. Also holds the Dev ID buff ID and
---Aug Breath of Eons cast spellIDs so neither needs its own top-level local.
---  charges       — Aug ID charges remaining (0..6), from UNIT_SPELLCAST_SUCCEEDED.
---  baseCost      — Eruption cost with no ID and no EB, cached from the API on
---                  every EB-inactive refresh. Used to reconstruct display cost
---                  during EB when the API returns 0.
---  spec          — Cached C_SpecializationInfo.GetSpecialization() result.
---                  Refreshed by Refresh (which already runs on spec change).
---                  updateEssenceBurstCost reads from here to avoid engine
---                  calls on every Breath/Eruption cast or aura tick.
---  tracker       — event frame; nil when disabled / non-Aug / setting off.
---  breathSpells  — Aug Breath of Eons cast spellIDs that grant 6 ID charges.
---  volcanism     — Aug Volcanism passive spellID; reduces Eruption cost by 1
---                  when known. Consulted whenever the fallback base path runs
---                  (API unavailable, /reload-mid-EB, etc.) so the cached base
---                  reflects the talented cost rather than the untalented seed.
---@class CUEAugIDState
---@field charges integer
---@field baseCost integer?
---@field spec integer?
---@field tracker frame?
---@field breathSpells table<integer, boolean>
---@field volcanism integer
local augID = {
    charges = 0,
    baseCost = nil,
    spec = nil,
    tracker = nil,
    breathSpells = { [403631] = true, [442204] = true },
    volcanism = 406904,
}

---Engine-driven Essence Burst overlay, and since the CDM viewer-child scan was
---deleted, the only one. It reads nothing: the engine shows a slot's button
---while the buff is up, and the addon only decides which slots are in the cost
---window. That is what took Evoker off the CDM keep-alive bridge.
---
---One AuraContainer PER SLOT — that part is still forced. The burst block
---covers slots 1..essenceBurstCost and that window moves in combat (Imminent
---Destruction), so the gate has to be writable in combat, which means a
---container SetShown, and one container can only carry one gate. See
---auraTap.ensureFill for why nothing below the slot button is writable.
---Per-SLOT, though, not per-slot-per-spec: three containers total.
---
---Rendered = button shown (engine: EB present) AND container shown (addon:
---slot is inside the cost window). Neither half is ever read back.
---
---Two behaviours the CDM path had and this one cannot, both consequences of
---never holding the boolean. Both were accepted when the scan was deleted:
---  * The charging bar no longer shifts behind the burst block during EB; it
---    stays at its true slot and is covered by the overlay while it sits
---    inside the block. (`burstShift` and its `essenceBurstActive` flag were
---    deleted with the scan — nothing could ever set them again.)
---  * An ID transition INSIDE an EB window is missed (see updateEssenceBurstCost).
---
---ONE set of slots, re-filtered on spec change. `SetAuraSlotCandidateFilters`
---is a plain Lua mixin with no combat gate (see auraTap.setSlotFilter), so a
---spec swap re-points the existing slots rather than standing up a second set.
---An earlier revision keyed the slots by spec and hid the outgoing set; that
---was built on the belief that candidate-filter calls were combat-restricted,
---which the Blizzard source does not support.
---
---  ids      — spec -> {spellID = true}, the candidate filter per spec.
---  spec     — spec the live slots are currently filtered for; `filterSpec`
---             changes drive exactly one re-point, since every
---             SetAuraSlotCandidateFilters ends in a full UpdateAllAuras().
---  cost     — last non-zero C_Spell.GetSpellPowerCost result.
---  maxSlots — highest EB spender cost across specs (Dev 3, Pres 2, Aug 3).
---@class CUEEssenceBurstTap
local ebTap = {
    ids = {},
    filterSpec = nil,
    cost = nil,
    maxSlots = 3,
}
for spec, buffID in pairs(ESSENCE_BURST_BUFF) do
    ebTap.ids[spec] = { [buffID] = true }
end

ebTap.slotKey = function(i)
    return "essenceburst_" .. i
end

---Builds (once) and gates the per-slot overlays, re-filtering them when the
---spec changes. Creation no-ops in combat and while auras are secret — callers
---re-invoke, so the first writable pass builds it. The SetShown gate and the
---filter re-point are both always live.
ebTap.apply = function()
    local spec = augID.spec

    local on = getSettings().evoker_essence_burst
        and playerPowerType == Enum.PowerType.Essence
        and spec ~= nil and ebTap.ids[spec] ~= nil

    -- Re-point before gating: a slot revealed on the same pass that changed
    -- spec must already be filtered for the spec it is about to show.
    if on and ebTap.filterSpec ~= spec then
        for i = 1, ebTap.maxSlots do
            auraTap.setSlotFilter(ebTap.slotKey(i), ebTap.ids[spec])
        end
        ebTap.filterSpec = spec
    end

    for i = 1, ebTap.maxSlots do
        local key = ebTap.slotKey(i)
        local rf = on and resourceFrames[i] or nil
        if rf then
            -- Creation bakes the filter in at AddAuraSlot time, so a slot built
            -- on this pass is already correct for `spec` — the re-point above
            -- has claimed filterSpec either way.
            auraTap.ensureFill(key, ebTap.ids[spec], rf,
                getSettings().evoker_essence_burst_color)
        end
        auraTap.setGlowEnabled(key, rf ~= nil
            and essenceBurstCost ~= nil
            and i <= essenceBurstCost
            and i <= activeResourceCount)
    end
end


---Queries C_Spell.GetSpellPowerCost for the spec's spender and returns the
---Essence cost entry, or 0 if the API is unavailable. Returning 0 (rather
---than the untalented seed) lets refreshEssenceBaseCost route the fallback
---through its talent-aware seeding path; otherwise the seed would land in
---the cost-known branch and bypass the Volcanism subtraction.
---Only meaningful when Essence Burst is NOT active (returns 0 during EB).
---@return integer
local function querySpenderEssenceCost()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local spellID = specIndex and ESSENCE_BURST_COST_SPELL[specIndex]
    if not spellID then return 0 end
    local costTable = C_Spell.GetSpellPowerCost(spellID)
    if costTable then
        for _, entry in ipairs(costTable) do
            if entry.type == Enum.PowerType.Essence then
                return entry.cost or 0
            end
        end
    end
    return 0
end

---Forward declaration; body assigned below after getResourceColor and getSettings are available.
---@type fun()
local applyEssenceBurstColors

---Refreshes the cached Eruption/Disintegrate base cost in augID.baseCost, plus
---the cached spec index in augID.spec. Called only on events that can actually
---change these values: PLAYER_SPECIALIZATION_CHANGED, PLAYER_ENTERING_WORLD,
---TRAIT_CONFIG_UPDATED / SPELLS_CHANGED (talent respec). This is the only place
---C_Spell.GetSpellPowerCost and IsPlayerSpell are called on the EB hot path —
---updateEssenceBurstCost reads the cached value afterward.
local function refreshEssenceBaseCost()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    augID.spec = specIndex

    local cost = querySpenderEssenceCost()
    if cost > 0 then
        -- API returned the talented cost. If ID is active right now the API
        -- value is 1 short of base; add it back so augID.baseCost represents
        -- the no-ID, no-EB cost.
        -- Taken as-is, ID reduction included: nothing reconstructs cost from a
        -- base any more, so the live API value IS the seed. Re-adding ID would
        -- mean the viewer scan that was deleted here.
        augID.baseCost = cost
        return
    end

    -- API returned 0 — either EB is active at refresh time (rare: /reload
    -- mid-EB or spec change mid-EB), the spell info hasn't loaded yet, or
    -- the spec has no EB spender (Pres). Seed from default plus known
    -- permanent cost-reducing talents.
    local base = (specIndex and ESSENCE_BURST_BASE_COST[specIndex]) or 0
    if specIndex == 3 and IsPlayerSpell(augID.volcanism) then
        base = base - 1
    end
    augID.baseCost = base
end

---Display-only: reads augID.baseCost and the live ID state and writes
---essenceBurstCost. Called on every EB-related aura/cast event, so it avoids
---all per-call engine queries — spec and talent state were pre-cached by
---refreshEssenceBaseCost at the last spec/talent event.
---
---ID state per spec:
---  Devastation (1): passive proc, one buff-viewer scan for buff 370781.
---  Augmentation (3): trivial — augID.charges is maintained by the spellcast
---                    tracker (augID.install) whenever Breath of Eons or
---                    Eruption fires.
local function updateEssenceBurstCost()
    -- Cost straight from the API, which already folds in talents AND the live
    -- ID reduction. The API returns 0 across the EB window (the spender is
    -- free), and holding the last non-zero value covers that: it is the cost as
    -- of EB start, i.e. what the pending spender would have cost. The one case
    -- it misses is an ID transition INSIDE an EB window; nothing recovers that,
    -- since ID's aura is secret in combat and the CDM scrape that used to
    -- reconstruct it is gone.
    local cost = querySpenderEssenceCost()
    if cost > 0 then ebTap.cost = cost end
    essenceBurstCost = ebTap.cost or augID.baseCost or 0
    ebTap.apply()
end

---Re-derives the Essence Burst cost window and repaints the overlays.
---
---The engine owns "is EB up" and nothing here reads it: `ebTap` binds each
---slot's container to the buff, so the tint appears and disappears without the
---addon ever holding the boolean. This used to scan the BuffIcon viewer's EB
---slot with a spender-glow fallback on the cooldown viewers — the last thing
---keeping the CDM keep-alive bridge up for Evoker (parity item K5).
local function refreshEssenceBurstState()
    updateEssenceBurstCost()
    essencePred.applyBorder()
end

deferredCallbacks["essenceBurst"] = refreshEssenceBurstState

---Evoker Essence-feature tracker. Two responsibilities, both event-driven so
---updateEssenceBurstCost stays cheap on the cast/aura hot path:
---  1. Aug-only: count Imminent Destruction charges via UNIT_SPELLCAST_SUCCEEDED
---     (Breath of Eons grants 6, each Eruption consumes one). The 459537 buff's
---     aura payload is secret on Aug, so we track it deterministically by cast.
---  2. Cross-spec: refresh augID.baseCost on spec change, talent change, and
---     /reload so the hot path never re-queries C_Spell.GetSpellPowerCost or
---     IsPlayerSpell per cast.
---
---Methods are attached to the augID table to avoid adding top-level locals
---(the file is at Lua 5.1's 200-local chunk limit).
augID.install = function()
    if not getSettings().evoker_essence_burst then return end
    if augID.tracker then return end
    local f = CreateFrame("Frame")
    augID.tracker = f
    if C_SpecializationInfo.GetSpecialization() == 3 then
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    -- Cost comes from C_Spell.GetSpellPowerCost rather than an ID aura read, so
    -- it needs a tick whenever a player aura changes. The payload is unused (and
    -- secret) — this is purely a "re-query now" signal, and markDirty coalesces
    -- it to at most one query per frame.
    f:RegisterUnitEvent("UNIT_AURA", "player")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("TRAIT_CONFIG_UPDATED")
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_AURA" then
            markDirty("essenceBurst")
            return
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit ~= "player" then return end
            if spellID == 395160 then
                if augID.charges > 0 then
                    augID.charges = augID.charges - 1
                    markDirty("essenceBurst")
                end
            elseif augID.breathSpells[spellID] then
                augID.charges = 6
                markDirty("essenceBurst")
            end
            return
        end
        -- PLAYER_SPECIALIZATION_CHANGED / PLAYER_ENTERING_WORLD / TRAIT_CONFIG_UPDATED.
        -- ID charges don't persist across these transitions; re-query cost.
        augID.charges = 0
        refreshEssenceBaseCost()
        -- Re-gate UNIT_SPELLCAST_SUCCEEDED based on the new spec so non-Aug
        -- players don't take per-cast event overhead.
        f:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        if augID.spec == 3 then
            f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        markDirty("essenceBurst")
    end)
end

augID.uninstall = function()
    if not augID.tracker then return end
    augID.tracker:UnregisterAllEvents()
    augID.tracker:SetScript("OnEvent", nil)
    augID.tracker = nil
    augID.charges = 0
    augID.baseCost = nil
end

---Returns the inclusive [start, finish] slot range covered by the prediction
---indicator. The indicator follows the Essence Burst tint — always slots
---1..essenceBurstCost — so border and tint sit on the same bars. Returns nil
---if no window applies (wrong power type, no slots, or no known cost).
essencePred.computeRange = function()
    if playerPowerType ~= Enum.PowerType.Essence then return nil end
    if activeResourceCount == 0 then return nil end
    if not essenceBurstCost or essenceBurstCost == 0 then return nil end
    local finish = essenceBurstCost
    if finish > activeResourceCount then finish = activeResourceCount end
    return 1, finish
end

---Lazy-creates the prediction-border overlay on a resource frame. Four
---ColorTexture edges parented to the resource frame, flush-anchored and
---extending inward 3px so the band sits entirely inside the bar. Frame level
---is +3 (above bar fill at +0, predictionBar at +1 and the Essence Burst tap
---fill at +2, below the configurable bar border at +5 — so any user-enabled
---bar border draws on top of this indicator rather than the other way around).
---The two Essence overlays cover the same slots whenever EB is up, and the
---border has to read on top of the fill rather than be masked by it.
essencePred.getOrCreateBorder = function(resourceFrame)
    local border = essencePred.borders[resourceFrame]
    if border then return border end
    border = CreateFrame("Frame", nil, resourceFrame)
    border:SetAllPoints(resourceFrame)
    border:SetFrameLevel(resourceFrame:GetFrameLevel() + 3)
    local edges = {}
    for i = 1, 4 do edges[i] = border:CreateTexture(nil, "OVERLAY") end
    edges[1]:SetPoint("TOPLEFT")
    edges[1]:SetPoint("TOPRIGHT")
    private.Pixel.SetHeight(edges[1], 3)
    edges[2]:SetPoint("BOTTOMLEFT")
    edges[2]:SetPoint("BOTTOMRIGHT")
    private.Pixel.SetHeight(edges[2], 3)
    edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT")
    edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
    private.Pixel.SetWidth(edges[3], 3)
    edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT")
    edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
    private.Pixel.SetWidth(edges[4], 3)
    border.edges = edges
    border:Hide()
    essencePred.borders[resourceFrame] = border
    return border
end

---Shows the prediction border on the slots in essencePred.computeRange();
---hides it everywhere else. Idempotent and allocation-free on the hot path
---(cached overlay frames, in-place color writes). Only touches addon-owned
---children — safe under combat lockdown.
essencePred.applyBorder = function()
    for _, border in pairs(essencePred.borders) do border:Hide() end
    if not getSettings().evoker_essence_prediction then return end
    local s, e = essencePred.computeRange()
    if not s then return end
    local color = getSettings().evoker_essence_burst_color
    local cr, cg, cb, ca = color[1], color[2], color[3], color[4] or 1
    for i = s, e do
        local rf = resourceFrames[i]
        if rf then
            local border = essencePred.getOrCreateBorder(rf)
            for _, edge in ipairs(border.edges) do edge:SetColorTexture(cr, cg, cb, ca) end
            border:Show()
        end
    end
end

---Applies Essence Burst color shift to the leftmost essenceBurstCost slots.
---Called from onUpdateEssence and refreshEssenceValues after bar values are set.
---Uses EvaluateColorValueFromBoolean to handle potentially secret boolean state.
applyEssenceBurstColors = function()
    if not getSettings().evoker_essence_burst then return end
    if not essenceBurstCost or essenceBurstCost == 0 then return end
    if playerPowerType ~= Enum.PowerType.Essence then
        return
    end

    -- The burst TINT is not applied here any more — `ebTap` draws it as an
    -- engine-shown overlay above the fill, so the addon never learns whether
    -- EB is up. What remains is the reset half: nothing else repaints Essence
    -- slots, so this keeps them at the resource colour underneath the overlay.
    local normalR, normalG, normalB = getResourceColor()
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetStatusBarColor(normalR, normalG, normalB, 1)
    end
end

-- ── Paladin Divine Purpose functions ─────────────────────────────────────────

---Highest Holy Power cap — one tint container per pip up to it.
local DIVINE_PURPOSE_MAX_PIPS = 5

---Engine-driven Divine Purpose tint over the FILLED Holy Power pips, the same
---shape as ebTap.apply: one auraTap.ensureFill container per pip. The engine
---shows each pip's slot button while the buff is up; the addon shows the
---container while the pip is filled. Holy Power is a plain value, and a
---container SetShown is combat-safe, so nothing below the slot button is ever
---written or read.
local function applyDivinePurposeTint()
    local on = getSettings().paladin_divine_purpose
        and playerPowerType == Enum.PowerType.HolyPower
    local current = on and SRC.staticPower(Enum.PowerType.HolyPower) or 0
    for i = 1, DIVINE_PURPOSE_MAX_PIPS do
        local key = "divinepurpose_" .. i
        local rf = on and resourceFrames[i] or nil
        if rf then
            auraTap.ensureFill(key, SRC.DIVINE_PURPOSE_BUFF_IDS, rf,
                getSettings().paladin_divine_purpose_color)
        end
        auraTap.setGlowEnabled(key, rf ~= nil
            and i <= current
            and i <= activeResourceCount)
    end
end

-- ── Marksmanship Hunter Lock and Load detection ─────────────────────────────

---Engine-driven Lock and Load indicator — the same aura-tap glow as Divine
---Purpose, around the Aimed Shot charge row.  The old path recolored every
---segment unconditionally off a CDM child's `IsShown()`, so a border spanning
---the row covers exactly the same area.
local function applyLockAndLoadGlow()
    if not getSettings().marksman_lock_and_load
        or playerPowerType ~= SRC.AIMED_SHOT_CHARGES then
        auraTap.setGlowEnabled("lockandload", false)
        return
    end
    auraTap.ensureGlow("lockandload", SRC.LOCK_AND_LOAD_BUFF_IDS, resourcesFrame,
        getSettings().marksman_lock_and_load_color)
    auraTap.setGlowEnabled("lockandload", true)
end

-- ── Devastation Evoker Unbound Flame expiry border ──────────────────────────

---Opt-in border around the Unbound Flame row, shown by the ENGINE while the
---buff sits inside its refresh-carryover window — the only "running out" cue
---that survives aura secrecy (see auraTap.ensurePandemic).
---
---Targets `rowFrame`, not `resourcesFrame`: this is an extra row, and a border
---spanning the component would enclose the Essence row as well. Devastation's
---primary is Essence and is not toggleable, so the strip is always row 2 and
---`rowFrames[2]` is pooled by index — the cached container keeps a valid anchor
---across row-count changes.
---
---Expected to stay dark: Unbound Flame is applied once and never refreshed, so
---Blizzard's carry-over arithmetic yields no window. Shipped opt-in and off so a
---dead cue costs nobody anything, and so the assumption can be tested in play
---rather than argued about.
local function applyUnboundFlameExpiry()
    if not getSettings().evoker_unbound_flame_expiry
        or playerPowerType ~= SRC.UNBOUND_FLAME then
        auraTap.setGlowEnabled("unboundflame", false)
        return
    end
    auraTap.ensurePandemic("unboundflame", { [SRC.UNBOUND_FLAME_AURA_ID] = true },
        rowFrame, getSettings().evoker_unbound_flame_expiry_color)
    auraTap.setGlowEnabled("unboundflame", true)
end

-- ── Essence (Evoker) tracking ───────────────────────────────────────────────

---Cached whole Essence count from the last UNIT_POWER_FREQUENT event.
---Read by onUpdateEssence to place the in-progress bar without calling UnitPower per frame.
---@type integer
cachedCurrentEssence = 0

---Option 2A: GetTime() anchor for the in-progress Essence bar. Set on integer gain
---(new bar starts at 0), preserved on spend (engine preserves partial), nil when at
---max. Seeded once from UnitPartialPower on initial enable to avoid a login flash.
---Stored on `private` to avoid the file's 200-local limit.
---@type number?
private.essenceStartTime = nil

---Option 2A: seconds required to fill one Essence bar, derived from Rebirth's
---cast time (spellID 361227): fillDuration = castTime / 2000 (castTime in ms).
---Rebirth's 10s base cast time is not modified by talents, buffs, or spec, so
---the realized castTime directly reflects haste — unlike the GCD, which has
---a 0.75s floor and talent-modified values. Carries over across enable/disable.
---@type number
private.essenceFillDuration = 5.0

---Debounce flag for haste sampling. Set by any event that might have changed
---haste (cast starts, cooldown updates, aura changes); consumed and cleared at
---the top of refreshEssenceValues and onUpdateEssence. This collapses many
---event fires per frame (UNIT_AURA + SPELL_UPDATE_COOLDOWN bursts in combat)
---into a single refreshEssenceFillDuration call per frame.
---Starts true so the first frame after enable seeds fillDuration.
---@type boolean
private.hasteDirty = true

---Cache the resolved (configID → nodeID) lookup for Innate Magic so we walk the
---class tree at most once per loadout. Stored on `private` to avoid the file's
---200-local limit.
---@type { configID: number?, nodeID: number? }
private.innateMagicResolved = private.innateMagicResolved or { configID = nil, nodeID = nil }

---Returns the Innate Magic multiplier to apply to Essence regen rate (1.00, 1.05, 1.10).
---Walks the class tree once per configID to find the node containing
---SRC.INNATE_MAGIC_ENTRY_ID, then reads activeRank. Respec invalidates via configID
---change; untalented state falls through to 1.0 (activeRank == 0 misses the bonus map).
---Stored on `private` to avoid the file's 200-local/upvalue limit.
private.innateMagicMultiplier = function()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return 1.0 end
    local resolved = private.innateMagicResolved
    if resolved.configID ~= configID then
        resolved.configID = configID
        resolved.nodeID = nil
        local cfg = C_Traits.GetConfigInfo(configID)
        if cfg and cfg.treeIDs then
            for _, treeID in ipairs(cfg.treeIDs) do
                for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
                    local ni = C_Traits.GetNodeInfo(configID, nodeID)
                    if ni and ni.entryIDs then
                        for _, entryID in ipairs(ni.entryIDs) do
                            if entryID == SRC.INNATE_MAGIC_ENTRY_ID then
                                resolved.nodeID = nodeID
                                break
                            end
                        end
                    end
                    if resolved.nodeID then break end
                end
                if resolved.nodeID then break end
            end
        end
    end
    if not resolved.nodeID then return 1.0 end
    local nodeInfo = C_Traits.GetNodeInfo(configID, resolved.nodeID)
    if not nodeInfo then return 1.0 end
    local bonus = SRC.INNATE_MAGIC_BONUS[nodeInfo.activeRank]
    return bonus and (1.0 + bonus) or 1.0
end

---Samples Rebirth's cast time (spellID 361227) and updates private.essenceFillDuration.
---Rebirth's 10s base cast time isn't modified by talents, buffs, or spec — the realized
---castTime directly reflects current haste, with no GCD-style floor or talent-induced
---anomalies, so no sanity clamp is needed.
---Formula: haste_mult = 10000 / castTime; fillDuration = 5.0 / haste_mult = castTime / 2000.
---Innate Magic (+5%/+10% Essence regen) divides fillDuration by its multiplier so the
---bar matches the engine's actual regen rate.
---When fillDuration actually changes and a bar is in progress, the anchor is
---shifted so the visible fraction is preserved (only the future rate changes),
---which avoids a visual jump on mid-bar haste shifts.
local refreshEssenceFillDuration = function()
    local info = C_Spell.GetSpellInfo(361227)
    if not info then return end
    local castTime = info.castTime
    if not castTime then return end
    local newFillDuration = (castTime / 2000) / private.innateMagicMultiplier()
    if newFillDuration == private.essenceFillDuration then return end
    if private.essenceStartTime then
        -- Re-anchor so the visible fraction stays put across the duration change.
        local now = GetTime()
        local fraction = math.min(1, (now - private.essenceStartTime) / private.essenceFillDuration)
        private.essenceStartTime = now - fraction * newFillDuration
    end
    private.essenceFillDuration = newFillDuration
end

---Reads UnitPower and refreshes the Essence bars.
---Option 2A: the in-progress bar is driven by (now - private.essenceStartTime) /
---private.essenceFillDuration. On integer gain the anchor is reset to now (new bar
---starts at 0); on spend the anchor is preserved (engine preserves partial regen).
---Returns true if Essence is not yet at maximum (caller keeps OnUpdate active).
local refreshEssenceValues = function()
    if private.hasteDirty then
        refreshEssenceFillDuration()
        private.hasteDirty = false
    end
    local current = UnitPower("player", playerPowerType)
    local max = UnitPowerMax("player", playerPowerType)
    local prevEssence = cachedCurrentEssence
    cachedCurrentEssence = current

    -- The charging bar used to shift to cost+1 while EB was up. That needed the
    -- EB boolean, which no longer exists (see ebTap) — the bar now stays at its
    -- true slot and the overlay simply covers it inside the block.
    local chargingSlot = current + 1

    for i = 1, activeResourceCount do
        if i <= current then
            resourceFrames[i].bar:SetValue(1)
        elseif i > chargingSlot then
            resourceFrames[i].bar:SetValue(0)
        end
    end

    if current >= max then
        private.essenceStartTime = nil
        applyEssenceBurstColors()
        essencePred.applyBorder()
        applyThresholdColors()
        return false
    end

    local now = GetTime()
    if private.essenceStartTime == nil then
        -- Initial sync (login, re-enable, spend-from-max with no prior anchor).
        -- Seed from UnitPartialPower once so the first bar visually matches the
        -- engine's carried-over partial instead of snapping to 0.
        local partial = (UnitPartialPower("player", playerPowerType) or 0) / 1000.0
        private.essenceStartTime = now - partial * private.essenceFillDuration
    elseif current > prevEssence then
        -- Integer gain: new in-progress bar starts at 0.
        private.essenceStartTime = now
    end
    -- current < prevEssence (spend): keep the anchor — engine preserves partial,
    -- so (now - anchor) rolls naturally into the new in-progress slot.
    -- current == prevEssence (partial-only event): no re-anchor.

    if chargingSlot <= activeResourceCount then
        local fraction = math.min(1, (now - private.essenceStartTime) / private.essenceFillDuration)
        resourceFrames[chargingSlot].bar:SetValue(fraction)
    end

    applyEssenceBurstColors()
    essencePred.applyBorder()
    applyThresholdColors()
    return true
end

---OnUpdate callback for Essence bars. Option 2A: drives the in-progress bar from
---(GetTime() - private.essenceStartTime) / private.essenceFillDuration. fillDuration
---is haste-derived from Rebirth's cast time (spellID 361227); the anchor is maintained
---by refreshEssenceValues across gain/spend events. No UnitPartialPower, no EMA.
---The OnUpdate is cleared by the event handler when refreshEssenceValues returns false.
local onUpdateEssence = function()
    if private.hasteDirty then
        refreshEssenceFillDuration()
        private.hasteDirty = false
    end
    local fraction = 0
    if private.essenceStartTime then
        fraction = math.min(1, (GetTime() - private.essenceStartTime) / private.essenceFillDuration)
    end

    -- See onUpdateEssence: the EB charging-bar shift went with the boolean.
    local inProgress = cachedCurrentEssence + 1

    for i = 1, activeResourceCount do
        if i <= cachedCurrentEssence then
            resourceFrames[i].bar:SetValue(1)
        elseif i == inProgress then
            resourceFrames[i].bar:SetValue(fraction)
        else
            resourceFrames[i].bar:SetValue(0)
        end
    end
    applyEssenceBurstColors()
    essencePred.applyBorder()
    applyThresholdColors()
    updateValueText()
end

-- ── Demon Hunter Soul Fragment update functions ──────────────────────────────

---Updates Vengeance Soul Fragment bars (discrete, like combo points).
---Each bar's MinMax is set to [i-1, i] so that SetValue(secret) auto-clamps:
---bars below the count show full, the threshold bar shows partial (0 or 1),
---and bars above show empty — no arithmetic on the secret value.
local updateVengeanceSoulFragments = function()
    if activeResourceCount == 0 then return end
    cachedVengeanceFragments = getVengeanceSoulFragments()
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(cachedVengeanceFragments, barInterpolation)
    end
    -- Tier B threshold fold — cachedVengeanceFragments is secret, flows through
    -- EvaluateColorFromBoolean (AllowedWhenTainted) via applyThresholdColorsSecret.
    local tr, tg, tb, ta = getCustomResourceColor()
    if tr then
        applyThresholdColorsSecret(cachedVengeanceFragments, CreateColor(tr, tg, tb, ta or 1))
    end
    updateValueText()
end

---Updates the Devourer Soul Fragment fill bar.
---Reads soul count via C_Spell.GetSpellCastCount and sets bar value (0–max).
local updateDevourerSoulFragments = function()
    if activeResourceCount == 0 then return end
    cachedDevourerSouls = getDevourerSoulCount()
    resourceFrames[1].bar:SetValue(cachedDevourerSouls, barInterpolation)
    reapFc.update()
    updateValueText()
end

---Checks if the Devourer max soul cap has changed (Metamorphosis or Soul Glutton)
---and updates the bar's min/max range accordingly.
local refreshDevourerMax = function()
    local newMax = getDevourerSoulMax()
    if newMax ~= cachedDevourerMax then
        cachedDevourerMax = newMax
        resourceFrames[1].bar:SetMinMaxValues(0, cachedDevourerMax)
    end
    reapFc.update()
end

-- ── Reap forecast helpers (methods on reapFc; see top-of-file declaration) ──

---Reap soul-consumption capacity. 10 with Moment of Craving (Reap is overridden
---by Eradicate 1225826), 4 otherwise.
---
---The Reap → Eradicate override is the ONLY signal. The MoC aura itself is
---unreadable: spell 1238488 is flagged `Passive spell` + `Aura is hidden` and
---does NOT carry "aura never secret", so `GetPlayerAuraBySpellID` returns nil
---for it exactly when it matters (see `.context/api.md` "Aura rules").
---
---This used to prefer the BuffIcon CDM viewer's MoC slot, whose non-secret
---`auraInstanceID` flipped off at expiry — the last thing pinning the CDM
---keep-alive bridge on for Demon Hunters (parity item K6). That is gone; the
---accuracy cost is stated on `startCapPoll` and is deliberate.
---@return integer
function reapFc.getCap()
    if C_Spell.GetOverrideSpell(1226019) == 1225826 then
        return reapFc.capMax
    end
    return 4
end

---Lazy-creates our own stacks FontString right of valueText and binds it into
---the aura tap ("soulfrags" slot). Blizzard writes the secret SF count into it
---directly (display-only; pass-through formatter renders 0/1 too). After the bind the FS
---is forbidden to tainted code while auras are secret — never GetText/SetShown/
---SetFont it in combat. Idempotent; safe to call every tick (auraTap.ensure
---self-guards on combat and already-bound).
function reapFc.ensureTapStacks()
    if not rowFrame or not rowFrame.valueText then return end
    auraTap.ensure("soulfrags", reapFc.sfIds, function(fs)
        -- PRE-BIND (inside initializeFrame, before SetApplicationCount):
        -- font styling only. The anchor comes from applyTapAnchors on the
        -- next tick — both FontStrings anchor to the ROW (rowFrame), a
        -- plain Frame target: font-to-font edges and frames anchored ONTO
        -- the bound FS are the combinations that hit the forbidden-aspect
        -- errors; FS → Frame is the proven-working shape.
        reapFc.tapStacks = fs
        reapFc.applyTapFont()
    end)
end

---Seam-centered composite, both sides anchored to the BAR: the configured
---value-font anchor point is the SEAM — valueText right-anchors 2px left of
---it (grows leftward, justified right), the tap FS left-anchors 2px right
---(grows rightward, justified left). Derived from PROFILE constants each
---time, never from a live GetPoint (no offset compounding). valueText writes
---are OURS and ungated (runs in combat — the Void-Meta fix); the tap FS
---write is gated on non-secret, and seamApplied is only set once BOTH sides
---are placed, so a blocked FS write retries next tick. active=false restores
---the profile anchor.
---
---Both halves anchor to the SAME frame: the row's own `rowFrame`. The bound tap
---FS used to keep a `resourcesFrame` edge, which was indistinguishable while
---there was only ever one row — `layoutRows(1)` does `SetAllPoints`, so the two
---rects coincide — but at two rows `resourcesFrame`'s centre is the boundary
---BETWEEN the rows, which would drop the nearby count half a row low, on top of
---whatever the second row draws.
---
---Moving it is legal because the anchor TARGET is not part of the bind. The FS
---is created on, and parented to, the aura slot button (`auraTap.ensure`'s
---`initializeFrame`) — that parentage is what `ValidateInboundScriptObject`
---checks — and positioning is cross-frame anchoring applied after the bind,
---gated on `not auraTap.blocked()`. What the topology note in
---`Components/SecondaryResources.md` calls proven is the SHAPE, "bound FS → plain
---Frame", and `rowFrame` is exactly that: `ensureRow` builds it as a plain
---addon-owned `CreateFrame("Frame", nil, resourcesFrame)`. The same move already
---ships for the other bound readout — `applyStackTapFont` anchors `stackTap.text`
---to `rowFrame` for precisely this reason.
---
---This is reached only from `updateValueText`'s `rowIndex == 1` guard, so
---`rowFrame` here is always row 1's.
function reapFc.applyTapAnchors(active)
    local vt = rowFrame and rowFrame.valueText
    if not vt then return end
    local valueFont = getSettings().value_font
    if not active then
        if reapFc.seamApplied then
            reapFc.seamApplied = false
            if valueFont then
                private.Util.ApplyFontProfile(vt, valueFont, rowFrame)
            end
            if not (valueFont and valueFont.anchor_point) then
                -- Creation-time default (ApplyFontProfile only positions when
                -- the profile carries an anchor).
                vt:ClearAllPoints()
                vt:SetPoint("CENTER", rowFrame, "CENTER", 0, 0)
                vt:SetJustifyH("CENTER")
            end
        end
        return
    end
    if reapFc.seamApplied or not reapFc.tapStacks then return end
    local pt = (valueFont and valueFont.anchor_point) or "CENTER"
    local x = (valueFont and valueFont.offset_x) or 0
    local y = (valueFont and valueFont.offset_y) or 0
    local vert = pt:match("^TOP") or pt:match("^BOTTOM") or ""
    vt:ClearAllPoints()
    vt:SetPoint(vert .. "RIGHT", rowFrame, pt, x - 2, y)
    vt:SetJustifyH("RIGHT")
    if auraTap.blocked() then return end
    reapFc.tapStacks:ClearAllPoints()
    reapFc.tapStacks:SetPoint(vert .. "LEFT", rowFrame, pt, x + 2, y)
    reapFc.seamApplied = true
end

---Applies the value-font profile to the tap FS MINUS its anchor branch
---(ApplyFontProfile's anchor_point path would SetPoint the bound FS onto
---resourcesFrame — an illegal cross-family edge). Face/size/outline/color/
---shadow only, plus seam justify. Writable moments only (bind, out-of-combat
---convergence tick).
function reapFc.applyTapFont()
    local fs = reapFc.tapStacks
    if not fs then return end
    local valueFont = getSettings().value_font
    if valueFont then
        local p = {}
        for k, v in pairs(valueFont) do p[k] = v end
        p.anchor_point = nil
        private.Util.ApplyFontProfile(fs, p, resourcesFrame)
    end
    fs:SetJustifyH("LEFT")
end



---Lazy-creates the overlay elements on resourceFrames[1]: preview texture,
---clip frames, and Collapsing Star breakpoint pip. Idempotent.
---The souls-nearby ammo bar is NOT here — it is the engine-driven bound bar
---built by reapFc.ensureTapAmmo into reapFc.ammoClip.
function reapFc.ensureOverlays()
    if reapFc.preview then return end
    local host = resourceFrames[1]
    if not host or not host.bar then return end

    -- Clipping container: parents the slab + ammo so we can SetWidth them to
    -- the (non-secret) reap cap pixel width without reading the secret-driven
    -- fill-texture geometry to clamp. When souls are at/near max the slab
    -- anchors to the fill seam and would extend past the bar's right edge;
    -- SetClipsChildren masks that overflow visually. Same pattern as
    -- fbClipFrame / asClipFrame.
    if not reapFc.clipFrame then
        local clip = CreateFrame("Frame", nil, host)
        clip:SetAllPoints(host)
        clip:SetClipsChildren(true)
        clip:SetFrameLevel(host.bar:GetFrameLevel() + 1)
        reapFc.clipFrame = clip
    end
    local clip = reapFc.clipFrame

    -- Cap-width scissor for the 12.1 ammo bar. The bound bar is capMax souls
    -- long and can never be resized while auras are secret; this frame is
    -- plain and addon-owned, so trimming it to the live cap width IS writable
    -- in combat. Nested inside clipFrame, so the bar-edge mask still applies.
    if not reapFc.ammoClip then
        local ammoClip = CreateFrame("Frame", nil, clip)
        ammoClip:SetClipsChildren(true)
        ammoClip:SetFrameLevel(clip:GetFrameLevel() + 1)
        reapFc.ammoClip = ammoClip
    end

    -- Reap-consumption preview: anchored to the soul bar's fill-texture RIGHT
    -- edge so it automatically tracks the current soul count (which may be a
    -- secret number — we never read it, we piggyback on the StatusBar fill).
    -- Width is pure non-secret arithmetic: (reapCap / cachedDevourerMax) * barWidth.
    -- Parented to the clip frame so any overflow past the bar's right edge
    -- (when souls are at/near max) is masked.
    if not reapFc.preview then
        local preview = clip:CreateTexture(nil, "OVERLAY", nil, 1)
        preview:SetSnapToPixelGrid(false)
        preview:SetTexelSnappingBias(0)
        preview:SetColorTexture(1.0, 0.85, 0.2, 0.55)
        preview:Hide()
        reapFc.preview = preview
    end

    -- Collapsing Star breakpoint pip: vertical 2px marker at 30 souls, shown
    -- only during Void Metamorphosis (VM form aura 1217607 present). CS is the
    -- VM-phase cast that unlocks at 30 souls. Parented to clip so it shares
    -- the same draw level as preview/ammo and is masked at the bar's edges.
    if not reapFc.pipCS then
        local pip = clip:CreateTexture(nil, "OVERLAY", nil, 2)
        pip:SetSnapToPixelGrid(false)
        pip:SetTexelSnappingBias(0)
        pip:SetColorTexture(0.9, 0.9, 0.9, 0.9)
        pip:SetWidth(2)
        pip:Hide()
        reapFc.pipCS = pip
    end

    -- Souls-nearby ammo sub-bar: StatusBar overlaying the preview region
    -- (same LEFT anchor at the soul-fill edge, same width as preview, full
    -- bar height). min/max = (0, reapCap), value = secret SF applications.
    -- When value < cap the StatusBar fill shows the fraction, leaving the
    -- preview-colored region visible beneath. Mirrors ReapMeter's sfBar.
    -- Anchor is set in update() once fillTex + widthPx are known. Parented
    -- to the clip frame so its right-edge overflow near max is masked too.
end

---Lazy-creates the 12.1 engine-driven ammo bar: a dedicated aura-tap
---container parented to the ammo clip frame (cap + bar-edge masking), slot
---bound to the SF aura, StatusBar styled like the legacy ammo bar.
---maxApplications is the FIXED `capMax`, never the live cap — see
---`reapFc.updateTapAmmo`. Idempotent.
function reapFc.ensureTapAmmo()
    if not reapFc.ammoClip or auraTap.bars["reapammo"] then return end
    local s = getSettings()
    local ac = s.devourer_reap_ammo_color or {1.0, 0.9, 0.3, 1}
    auraTap.ensureBar("reapammo", reapFc.sfIds, reapFc.ammoClip,
        reapFc.capMax, function(bar)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local tex = bar:GetStatusBarTexture()
            if tex then
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
            end
            bar:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1)
        end)
    local c = auraTap.barContainers["reapammo"]
    if c then
        -- clipFrame = host.bar + 1, ammoClip = +2; +1 more puts the button
        -- subtree at the legacy ammo's host.bar + 3, above the preview slab.
        c:SetFrameLevel(reapFc.ammoClip:GetFrameLevel() + 1)
    end
end

---Per-update geometry for the 12.1 ammo bar. Both the slot BUTTON and the
---clip frame anchor to the live fill seam (fillTex right edge), so the seam
---tracks engine-side with zero per-frame Lua; Blizzard drives the fill value.
---
---> **The cap is applied by the SCISSOR, not by the bind.** The button is
---> `DenyTaintedAccessWhenAurasAreSecret`, so its width and the bound bar's
---> `maxApplications` are writable only while auras are non-secret — i.e. out
---> of combat. But the cap flips on the Reap → Eradicate override, which only
---> ever happens IN combat, so a cap-scaled bind could never converge while it
---> mattered: the preview slab (a plain addon Texture, freely resizable) grew
---> to the 10-cap width while the ammo bar stayed at its 4-cap scale, and the
---> extended range never filled. Live-reported 2026-08-29.
---
---So the button is a FIXED `capMax` souls long — set once, never rewritten —
---and `ammoClip`, an addon-owned frame, is trimmed to the live cap width every
---pass. Fill is `applications / capMax` of a capMax-wide button, i.e. exactly
---one soul-width per application at any cap, and the scissor hides whatever
---Reap could not consume. Container Show/Hide is ours and carries the
---spec/setting gate.
function reapFc.updateTapAmmo(fillTex, capWidthPx, fullWidthPx)
    -- Combat-writable: plain addon frame, and the only per-cap geometry left.
    -- Sized BEFORE the container is created inside it so the scissor has a
    -- resolvable rect from the first frame.
    local clip = reapFc.ammoClip
    if not clip then return end
    -- The button's width bakes the soul→pixel scale (barWidth / soul max) at
    -- its last writable pass, and both inputs can move afterwards while the
    -- button cannot be rewritten: cachedDevourerMax is 50, 35 with Soul
    -- Glutton, and 40 in Void Metamorphosis — a mid-pull change. SetScale on
    -- this frame is ours and combat-legal, so it carries the correction; the
    -- clip's own width divides it back out to stay in screen pixels.
    local baked = reapFc.ammoBaked
    local scale = (baked and baked > 0) and (fullWidthPx / baked) or 1
    clip:SetScale(scale)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    clip:SetWidth(capWidthPx / scale)
    clip:Show()

    reapFc.ensureTapAmmo()
    local c = auraTap.barContainers["reapammo"]
    if not c then return end -- creation deferred (combat); retry next tick
    c:Show()
    if auraTap.blocked() then return end
    local btn = auraTap.barButtons["reapammo"]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
    btn:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    btn:SetWidth(fullWidthPx)
    -- Re-baked at the live scale, so the correction above collapses to 1.
    reapFc.ammoBaked = fullWidthPx
    clip:SetScale(1)
    clip:SetWidth(capWidthPx)
end

---Hides every reapFc overlay. Used by the spec gate in `update()` and by
---`refreshResourceCount` so overlays don't bleed into Vengeance / other
---power types that share resourceFrames[1] as their host frame.
function reapFc.hideAll()
    if reapFc.preview then reapFc.preview:Hide() end
    if reapFc.pipCS then reapFc.pipCS:Hide() end
    -- Hides the tap container with it — it lives inside this clip frame.
    if reapFc.ammoClip then reapFc.ammoClip:Hide() end
    reapFc.stopCapPoll()
end

---Starts a 0.25s ticker that re-runs the forecast once the Reap override
---reverts from Eradicate to Reap. SPELLS_CHANGED fires on MoC application but
---is not relied on for the revert, so this ticker owns that edge. Idempotent.
---
---> **The inaccuracy this was expected to cost does not exist.** The worry was
---> that the override reverts on Eradicate *consumption* only, so a Moment of
---> Craving that timed out unspent would strand the cap at 10 and the slab 10
---> souls wide until the next Eradicate — unfixable, since polling re-reads
---> the same override and the aura itself is hidden and secret (see
---> `reapFc.getCap`). **MoC carries no duration** (live 2026-08-30), so there
---> is no unspent-expiry case: consumption is the only exit, and that is the
---> edge this ticker owns. Verified in play — the slab falls back correctly.
---> The trade that freed every Demon Hunter from the CDM keep-alive turned out
---> to cost nothing at all.
---
---> Do not "simplify" this away on the strength of that. The ticker is what
---> detects the consumption edge; SPELLS_CHANGED covers application only.
function reapFc.startCapPoll()
    if reapFc.capPoll then return end
    reapFc.capPoll = C_Timer.NewTicker(0.25, function()
        if reapFc.getCap() ~= 10 then
            reapFc.update()
        end
    end)
end

---Cancels the cap-poll ticker if running. Idempotent.
function reapFc.stopCapPoll()
    if reapFc.capPoll then
        reapFc.capPoll:Cancel()
        reapFc.capPoll = nil
    end
end

---Refreshes overlay colors from current profile settings.
function reapFc.applyColors()
    local s = getSettings()
    if reapFc.preview then
        local pv = s.devourer_reap_preview_color or {1.0, 0.85, 0.2, 0.55}
        reapFc.preview:SetColorTexture(pv[1], pv[2], pv[3], pv[4] or 0.55)
    end
    local ac = s.devourer_reap_ammo_color or {1.0, 0.9, 0.3, 1}
    local tapAmmo = auraTap.bars["reapammo"]
    if tapAmmo and not auraTap.blocked() then
        -- Bound bar: writable out of combat only (DenyTaintedAccessWhenAurasAreSecret).
        tapAmmo:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1)
    end
    if reapFc.pipCS then
        local pc = s.devourer_reap_pip_color or {0.9, 0.9, 0.9, 0.9}
        reapFc.pipCS:SetColorTexture(pc[1], pc[2], pc[3], pc[4] or 0.9)
    end
end

---Drives all forecast visuals: preview texture, ammo bar, breakpoint pip.
---All arithmetic is on non-secret values; secret values (SF applications) go
---directly into AllowedWhenTainted sinks (SetValue).
function reapFc.update()
    -- Spec gate: the forecast only makes sense for Devourer DH. resourceFrames[1]
    -- is shared with Vengeance (first soul-fragment segment) and every other
    -- single-bar power type, so without this gate stale overlays bleed into
    -- those bars on spec switch and any incidental call into update() runs
    -- arithmetic against the wrong bar's geometry.
    if playerPowerType ~= SRC.SOUL_FRAG_DEVOURER then
        reapFc.hideAll()
        return
    end

    local s = getSettings()
    local host = resourceFrames[1]
    if not host or not host.bar then return end

    if not s.devourer_reap_forecast then
        reapFc.hideAll()
        return
    end

    reapFc.ensureOverlays()
    if not reapFc.preview then return end

    reapFc.applyColors()

    local barWidth = host:GetWidth()
    if barWidth <= 0 then
        C_Timer.After(0, reapFc.update)
        return
    end

    local cap = reapFc.getCap()
    if cap == 10 then
        reapFc.startCapPoll()
    else
        reapFc.stopCapPoll()
    end
    local max = cachedDevourerMax > 0 and cachedDevourerMax or 50
    -- Pure non-secret arithmetic. The fill-texture pixel width derives from
    -- the bar's SetValue(cachedDevourerSouls) — `cachedDevourerSouls` is a
    -- secret number, so reading `fillTex:GetWidth()` back into Lua propagates
    -- that taint (the prior approach hit "arithmetic on a secret number value"
    -- inside protected execution). Instead we SetWidth(capWidthPx) and rely on
    -- `reapFc.clipFrame`'s SetClipsChildren to mask the overflow when the fill
    -- seam is near the bar's right edge.
    local widthPx = barWidth * (math.min(cap, max) / max)
    -- Fixed-scale width for the 12.1 ammo button (see reapFc.updateTapAmmo).
    local fullWidthPx = barWidth * (math.min(reapFc.capMax, max) / max)
    local fillTex = host.bar:GetStatusBarTexture()

    -- The preview slab stays on 12.1 — it derives from live shard data via
    -- the engine-side fill seam (SetValue sink) + non-secret cap/max math,
    -- no aura reads. Only the aura-fed ammo overlay and the VM-gated pip are
    -- dead (gated below / in the pip branch).
    if fillTex and widthPx > 0 then
        reapFc.preview:ClearAllPoints()
        reapFc.preview:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        reapFc.preview:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
        reapFc.preview:SetWidth(widthPx)
        reapFc.preview:Show()

        -- Engine-driven ammo — Blizzard writes the secret SF applications
        -- into the bound StatusBar; we own geometry only.
        reapFc.updateTapAmmo(fillTex, widthPx, fullWidthPx)
    else
        reapFc.preview:Hide()
        if reapFc.ammoClip then reapFc.ammoClip:Hide() end
    end

    -- Collapsing Star threshold pip (30 souls) — visible only during Void
    -- Metamorphosis; in build phase the CS cast is unavailable, so hide.
    if reapFc.pipCS then
        -- Void Metamorphosis READS THROUGH the secret-aura lockdown, so this
        -- is a live check. It used to be hard-gated off on the assumption
        -- the read returns nil while
        -- secret — wrong, and the same wrong assumption would have made
        -- `getDevourerSoulMax`'s 40-cap branch dead code. Proof is that the
        -- branch is NOT dead: the ammo bar's soul→pixel scale visibly shifts
        -- on entering meta, which only happens if cachedDevourerMax reached
        -- 40, which only happens if this exact read returned data in combat
        -- (see reapFc.updateTapAmmo, and `.context/api.md` "Aura rules").
        -- Fails safe either way — a nil read just hides the pip, as before.
        local inVM = C_UnitAuras.GetPlayerAuraBySpellID(1217607) ~= nil
        local csThreshold = reapFc.pipCSThreshold
        if inVM and csThreshold and csThreshold < max then
            local offsetPx = barWidth * (csThreshold / max)
            reapFc.pipCS:ClearAllPoints()
            reapFc.pipCS:SetPoint("TOP", host, "TOPLEFT", offsetPx, 0)
            reapFc.pipCS:SetPoint("BOTTOM", host, "BOTTOMLEFT", offsetPx, 0)
            reapFc.pipCS:Show()
        else
            reapFc.pipCS:Hide()
        end
    end

end

-- ── Brewmaster Stagger update functions ──────────────────────────────────────

---Updates the Brewmaster Stagger fill bar, color, and cached percentage.
---Color thresholds: Heavy >= 60%, Moderate >= 30%, Light < 30%.
---When stagger_pips is enabled, section backgrounds handle the bg color instead.
local updateStaggerBar = function()
    if activeResourceCount == 0 then return end
    local maxHealth = UnitHealthMax("player")
    cachedStaggerPct = maxHealth > 0 and (UnitStagger("player") / maxHealth * 100) or 0
    resourceFrames[1].bar:SetValue(cachedStaggerPct, barInterpolation)
    local r, g, b, a = getStaggerColor()
    resourceFrames[1].bar:SetStatusBarColor(r, g, b, a)
    if not getSettings().stagger_pips then
        resourceFrames[1].bg:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, 0.8)
    end
    updateValueText()
end

---Updates a continuous-power fill bar (Elemental Maelstrom, Balance Astral Power,
---Shadow Insanity). Single bar: value from UnitPower; the max is set on the layout
---pass (refreshResourceCount) and on UNIT_MAXPOWER. Color is applied centrally by
---applyColors; breakpoint pip zone alphas / fill-color curves re-evaluate here
---per tick (secret-safe, allocation-free).
local updateContinuousBar = function()
    if activeResourceCount == 0 then return end
    resourceFrames[1].bar:SetValue(UnitPower("player", playerPowerType), barInterpolation)
    private.BreakpointPips.UpdateDynamic(continuousPipHost)
    updateValueText()
end


-- ── Monk Vitality (Aspect of Harmony) functions ─────────────────────────────

---Returns the current vitality amount from whichever storing buff tier is active.
---Checks all three tier auras (low/mid/high) — only one is active at a time.
---Falls back to the spending buff if no storing buff is found.
---Returns the aura points value (secret in Midnight; SetValue handles it).
---@return number|nil vitalityAmount
local function getVitalityAmount()
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(450521)   -- Vitality Store Low
        or C_UnitAuras.GetPlayerAuraBySpellID(450526)            -- Vitality Store Mid
        or C_UnitAuras.GetPlayerAuraBySpellID(450531)            -- Vitality Store High
        or C_UnitAuras.GetPlayerAuraBySpellID(450769)            -- Vitality Spend
    if aura and aura.points and aura.points[1] then
        return aura.points[1]
    end
    return 0
end

---Updates the Vitality fill bar value.
---Vitality amount is a secret value in Midnight; SetValue handles it via AllowedWhenTainted.
updateVitalityBar = function()
    if activeResourceCount == 0 then return end
    resourceFrames[1].bar:SetValue(getVitalityAmount(), barInterpolation)
    updateValueText()
end

---Refreshes the Vitality bar max range from UnitHealthMax.
---Both vitality amount and UnitHealthMax return secret values in Midnight;
---SetMinMaxValues handles them via AllowedWhenTainted.
local refreshVitalityMax = function()
    if activeResourceCount == 0 then return end
    resourceFrames[1].bar:SetMinMaxValues(0, UnitHealthMax("player"))
end

---Creates and registers the UNIT_AURA event frame for Vitality tracking.
---Like TotS, re-queries the aura on every UNIT_AURA fire (the event does not
---pass individual spellIDs as positional arguments).
local function registerVitalityEvents()
    if not vitalityEventFrame then
        vitalityEventFrame = CreateFrame("Frame")
        vitalityEventFrame:SetScript("OnEvent", function()
            updateVitalityBar()
        end)
    end
    vitalityEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
end

---Unregisters Vitality aura events.
local function unregisterVitalityEvents()
    if vitalityEventFrame then
        vitalityEventFrame:UnregisterAllEvents()
    end
end

-- ── Protection Warrior Ignore Pain functions ─────────────────────────────────

---Applies the value-font profile to the bound tap FS MINUS its anchor branch
---(ApplyFontProfile's anchor_point path would SetPoint the bound FS onto
---resourcesFrame — an illegal cross-family edge). The anchor goes in-family on
---the button instead, at the profile's own point and offsets; the button spans
---the host bar, so that lands where valueText would have. Writable moments only
---(bind, out-of-combat convergence tick).
ipState.applyTapFont = function()
    local fs = ipState.tapText
    if not fs or not ipState.tapButton then return end
    if auraTap.blocked() then
        -- fontsDirty passes only run on config changes, so "wait for the next
        -- pass" would never converge — updateBar drains this flag instead.
        ipState.tapFontDirty = true
        return
    end
    ipState.tapFontDirty = false
    local valueFont = getSettings().value_font
    local pt, x, y = "CENTER", 0, 0
    if valueFont then
        local p = {}
        for k, v in pairs(valueFont) do p[k] = v end
        p.anchor_point = nil
        private.Util.ApplyFontProfile(fs, p, resourcesFrame)
        pt = valueFont.anchor_point or pt
        x = valueFont.offset_x or 0
        y = valueFont.offset_y or 0
    end
    fs:ClearAllPoints()
    fs:SetPoint(pt, ipState.tapButton, pt, x, y)
end

---Lazy-creates the 12.1 engine-driven Ignore Pain readout: a dedicated aura-tap
---container whose slot button carries BOTH the fill bar and the value text, so
---the engine shows/hides and updates them with the aura. The CDM child scan that
---used to feed them is dead while auras are secret — i.e. for the whole pull —
---which left the bar at 0 and the text hidden exactly when Ignore Pain matters.
---Bindings per display mode:
---  stacks: SetApplicationBar(0..IGNORE_PAIN_MAX_STACKS) + SetDurationText
---  time:   SetDurationBar(RemainingTime)                + SetApplicationCount
---A bound object can never be re-bound (GetValidatedForbiddenObjectTable rejects
---access-constrained objects), so a mode flip RELEASES the slot and the next
---pass rebuilds it, leaking the abandoned container once per flip (a rare,
---out-of-combat settings change).
---No-op in combat / while auras are secret; updateBar re-invokes every tick, so
---the first writable one builds it.
ipState.ensureTap = function()
    local host = resourceFrames[1]
    if not host or not resourcesFrame then return end
    local timeMode = getSettings().protection_ignore_pain_time_bar and true or false
    if ipState.tapContainer then
        if ipState.tapTimeMode == timeMode then
            -- Re-show after unregisterIgnorePainEvents hid it (idempotent).
            ipState.tapContainer:Show()
            return
        end
        ipState.tapContainer:SetEnabled(false)
        ipState.tapContainer:Hide()
        ipState.tapContainer = nil
        ipState.tapButton = nil
        ipState.tapBar = nil
        ipState.tapText = nil
        -- The pandemic host lives on the released button; it goes with it.
        ipState.pandemicHost = nil
        ipState.pandemicBorder = nil
        ipState.pandemicKey = nil
    end
    if InCombatLockdown() or auraTap.blocked() then return end
    local texture = getSettings().texture
    -- Same resolution order as applyColors, which converges this bar later.
    local barR, barG, barB, barA = getCustomResourceColor()
    if not barR then barR, barG, barB, barA = getResourceColor() end
    local c = LAC:CreateContainer("CUE_SR_IgnorePainTap", host)
    c:SetUnit("player")
    c:SetSize(1, 1)
    c:SetPoint("TOPLEFT")
    c:SetEnabled(true)
    c:Show()
    -- Above the (permanently empty) host fill, below the pandemic overlay at +2
    -- and any user bar border at +5.
    c:SetFrameLevel(host.bar:GetFrameLevel() + 1)
    local button = c:AddAuraSlot("ignorepain", "HELPFUL", {
        candidateFilters = { includeSpellIDs = { [SRC.IGNORE_PAIN_SPELL_ID] = true } },
        initializeFrame = function(btn)
            -- PRE-BIND: creation + styling only, NO anchors in this context
            -- (SetPoint errors under UntrustedLayoutScriptExecution). The font
            -- object must be set before the bind — it pushes text immediately
            -- and a font-less SetText errors "Font not set".
            local bar = CreateFrame("StatusBar", nil, btn)
            applyTexture(bar, texture)
            bar:SetStatusBarColor(barR, barG, barB, barA)
            local fs = btn:CreateFontString(nil, "OVERLAY")
            fs:SetFontObject(GameFontNormal)
            if timeMode then
                btn:SetDurationBar(bar, {
                    direction = Enum.StatusBarTimerDirection.RemainingTime,
                })
                -- Pass-through formatter: Blizzard's formatter-less default
                -- renders "" below 2, and a 1-stack absorb still matters.
                local fmt = C_StringUtil.CreateNumericRuleFormatter()
                fmt:AddBreakpoint({ threshold = 0, format = "%d" })
                btn:SetApplicationCount(fs, { formatter = fmt })
            else
                btn:SetApplicationBar(bar, {
                    maxApplications = SRC.IGNORE_PAIN_MAX_STACKS,
                })
                btn:SetDurationText(fs)
            end
            ipState.tapBar = bar
            ipState.tapText = fs

            -- Pandemic HOST for AddPandemicRegion: a descendant of the button
            -- (ValidateInboundScriptObject rejects anything else) whose SHOWN
            -- state the engine drives inside the refresh-carryover window.
            -- Created here, pre-bind, because initializeFrame runs before the
            -- provider applies access restrictions; anchored post-return.
            --
            -- Static, like the trackers': the engine's window is binary, so a
            -- pulse would track nothing.
            local pHost = CreateFrame("Frame", nil, btn)
            local pBorder = CreateFrame("Frame", nil, pHost, "BackdropTemplate")
            pBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
            pBorder:SetBackdropBorderColor(1, 0, 0, 1)
            -- An UNREGISTERED host is plain-shown, so the border must start
            -- hidden; syncPandemic shows it only once the region is live.
            pBorder:Hide()
            ipState.pandemicHost = pHost
            ipState.pandemicBorder = pBorder
        end,
    })
    ipState.tapContainer = c
    ipState.tapButton = button
    ipState.tapTimeMode = timeMode
    ipState.pandemicKey = nil
    -- Post-return anchors: button -> host bar is the ONE cross-frame edge and a
    -- LIVE anchor (it tracks resizes with no further writes); the bar is
    -- in-family on the button.
    button:SetAllPoints(host.bar)
    ipState.tapBar:SetAllPoints(button)
    -- Both in-family on the button. The host is never Show/Hidden by us once
    -- registered — AddPandemicRegion stamps SecretAspect.Shown on it and the
    -- engine owns it from then on; the BORDER carries the plain shown state.
    ipState.pandemicHost:SetAllPoints(button)
    ipState.pandemicBorder:SetAllPoints(ipState.pandemicHost)
    ipState.applyTapFont()
end

---Registers or removes the tap button's native pandemic region to match
---`protection_ignore_pain_pandemic`, and shows/hides the border to match.
---
---This replaced a `DurationObject` curve driven from an `auraInstanceID` that
---only a CDM viewer-child scan could supply — a route that returns nil for the
---whole of every pull, i.e. dead exactly when an Ignore Pain refresh cue
---matters. `AddPandemicRegion` hands the engine an addon-owned Region and it
---drives the region's SHOWN state itself, so nothing crosses into Lua and no
---CDM child is involved.
---
---Trade-off, same as the trackers': the window is Blizzard's and binary, so
---there is no remaining-% to fade or colour-ramp against. The border is one
---colour at one alpha, drawn static.
---
---Never touch the HOST's shown state: `AddPandemicRegion` stamps
---`SecretAspect.Shown` on it. The border keeps a plain shown state of its own
---and the host's engine-driven visibility cascades to it.
ipState.syncPandemic = function()
    local button, host = ipState.tapButton, ipState.pandemicHost
    if not button or not host or not button.AddPandemicRegion then return end
    -- The host subtree is off limits while auras are secret
    -- (DenyTaintedAccessWhenAurasAreSecret cascades from the button), and so is
    -- Add/RemovePandemicRegion. updateBar re-invokes every pass, so the first
    -- readable one converges.
    if auraTap.blocked() then return end

    local want = getSettings().protection_ignore_pain_pandemic and true or false
    if want ~= (ipState.pandemicKey ~= nil) then
        if want then
            -- 12.1.0 returns an index to remove by; 12.1.5 / Forever return
            -- nothing and remove by the region itself.
            ipState.pandemicKey = button:AddPandemicRegion(host) or host
        else
            button:RemovePandemicRegion(ipState.pandemicKey)
            ipState.pandemicKey = nil
        end
    end
    -- RemovePandemicRegion drops the host from the engine's iteration without
    -- hiding it, so an unregistered host keeps whatever state was last written
    -- — the border must carry the off state itself.
    ipState.pandemicBorder:SetShown(ipState.pandemicKey ~= nil)
end

---Converges the Ignore Pain readout. The bar and text are engine-driven off the
---aura tap; this pass only builds/rebuilds it, suppresses the addon-owned
---valueText the tap replaces, and converges the native pandemic region.
ipState.updateBar = function()
    if activeResourceCount == 0 then return end
    ipState.ensureTap()
    if ipState.tapFontDirty then ipState.applyTapFont() end
    if ipState.tapText and rowFrame and rowFrame.valueText then
        rowFrame.valueText:Hide()
    end
    ipState.syncPandemic()
end

---Unregisters Ignore Pain tracking and resets state. The tap container carries
---the readout, so it is hidden here too — the next updateBar pass re-shows it.
local function unregisterIgnorePainEvents()
    -- The pandemic border rides the tap button, so hiding the container takes
    -- it with it; the region registration is left alone (touching it here would
    -- need the secrecy gate, and the next updateBar converges it anyway).
    if ipState.tapContainer then
        ipState.tapContainer:Hide()
    end
end

-- ── Engine-driven stack strips (the six `stackPipSpec` produces) ─────────────
--
-- Each renders one SECRET `applications` count as N discrete pips plus
-- a numeric readout, so they share one implementation. Nothing is read: the pips
-- are N slot-bound StatusBars (auraTap.ensurePips) and the readout is a bound
-- FontString (auraTap.ensure), both written by the engine.
--
-- This replaced a CDM viewer-child scan feeding an instance-ID aura read,
-- which returns nil while auras are secret — i.e. for the whole of every pull
-- — so both strips read 0 stacks exactly when they mattered. The scan is gone, and
-- with it the BuffIcon/BuffBar OnUnitAura hooks: neither resource registers an
-- event any more.

---Frost Mage Shatter. The only stack strip bound to a unit other than the
---player, which is what the extra `unit`/`filter` arguments on
---`auraTap.ensurePips` exist for. Fields: tapKey (the row-scoped pip-set key,
---stamped when the strip is built, so the target watcher can find the set
---without knowing which row it landed in), eventFrame (lazily created).
shatterState = { tapKey = nil, eventFrame = nil }

---Points the Shatter strip at the current target, or shuts it off.
---
---`SetEnabled(false)` is the shutdown, NOT an emptied spell-ID map: a
---HARMFUL|PLAYER container on a unit the player can assist fails
---`CanApplyIdentityCandidateFilters`, and a failed gate makes Blizzard SKIP
---`includeSpellIDs` altogether — which admits every aura rather than none
---(`.context/api.md`). `ParseAuras` early-returns on a disabled container, so
---this is the only gate-proof off switch.
---@param refresh boolean|nil  re-parse even when the unit token has not moved.
---  The event path passes true; the Refresh path must not, because it runs
---  hundreds of times a second in combat and `UpdateAllAuras` re-parses every
---  pip.
shatterState.syncTarget = function(refresh)
    local key = shatterState.tapKey
    local set = key and auraTap.pipSets[key]
    if not set then return end
    -- The threshold border (`ensureBorder`) is its own container bound to the
    -- same unit and filter, so it needs the same gate and the same swap refresh.
    local border = auraTap.borderSets[key]
    -- Mirrors `AuraContainerUtil.CanApplyIdentityCandidateFilters`
    -- (`Blizzard_AuraContainerUtil.lua:33-38`): for a HARMFUL aura it
    -- returns false -- i.e. skips `includeSpellIDs` -- when
    -- `UnitCanAssist("player", unitToken, canAssistImmune, canAssistUninteractable)`
    -- is true. The two trailing booleans are those two named arguments, and
    -- they are NOT optional noise: Blizzard passes them so immune and
    -- uninteractable units (vehicles, teleports, cutscenes) still count as
    -- assistable. Dropping them, or substituting a different predicate such as
    -- `UnitIsFriend`, makes this disagree with the engine -- and on the passes
    -- where it disagrees the filter is skipped, which admits EVERY aura on the
    -- target rather than none (`.context/api.md`). One engine branch is NOT
    -- mirrored: `:24` short-circuits to true for a NeverSecret-flagged spell,
    -- before the UnitCanAssist test. If Freezing ever gains that flag the
    -- engine would filter on an assistable target while this disables the
    -- container -- which fails closed (strip off), the safe direction.
    local hostile = UnitExists("target") and not UnitCanAssist("player", "target", true, true)
    set.container:SetEnabled(hostile)
    if border then border.container:SetEnabled(hostile) end
    if hostile then
        -- SetUnit is the FIRST BIND only: it early-outs on an unchanged token
        -- (`Blizzard_AuraContainer.lua:40`), and so does SetEnabled (`:28`), so
        -- a hostile -> hostile swap fires no container-side refresh at all and
        -- the strip keeps the previous target's stacks until the next UNIT_AURA
        -- on the new one. UpdateAllAuras is Blizzard's sanctioned external
        -- refresh hook ("e.g. target changes"), and is what the aura trackers
        -- already do on this event.
        set.container:SetUnit("target")
        if refresh then
            set.container:UpdateAllAuras()
            if border then border.container:UpdateAllAuras() end
        end
    end
end

shatterState.registerEvents = function()
    if not shatterState.eventFrame then
        shatterState.eventFrame = CreateFrame("Frame")
        shatterState.eventFrame:SetScript("OnEvent", function()
            shatterState.syncTarget(true)
        end)
    end
    shatterState.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- A target's reaction can flip with no target change at all (mind control, a
    -- neutral NPC turning), and reaction is the whole of the friendly/hostile
    -- gate above -- the same reason the aura trackers register it.  The player's
    -- own flips it too (being mind controlled), firing UNIT_FACTION for "player"
    -- only (Blizzard's TargetFrame.lua:200 reacts to both units).
    shatterState.eventFrame:RegisterUnitEvent("UNIT_FACTION", "target", "player")
end

---Drops the target watcher. `shatterState.eventFrame` is a DEDICATED frame, so
---`powerEventFrame:UnregisterAllEvents()` never reaches it — every teardown
---path (releaseRow via hideRowOverlays, OnDisable, ReevaluatePowerType, and the
---talent / spec-change / shapeshift handlers) has to call this by name. A path
---that skips it leaves PLAYER_TARGET_CHANGED live on an abandoned
---AuraContainer, which keeps re-pointing it on every target swap and parsing
---every UNIT_AURA engine-side; that costs no Lua memory, so nothing would ever
---report it. `registerPowerEvents` re-registers from `refreshRow`, so every
---re-enable re-acquires it.
shatterState.unregisterEvents = function()
    if shatterState.eventFrame then
        shatterState.eventFrame:UnregisterAllEvents()
    end
end

---Returns the current max Sweeping Strikes stacks based on Improved Sweeping
---Strikes talent (12 base, 18 with the talent).
---@return integer
ssState.getMaxStacks = function()
    return IsPlayerSpell(SRC.SS_IMPROVED_TALENT_ID) and SRC.SS_MAX_IMPROVED or SRC.SS_MAX_BASE
end

---How many segments a stack strip renders for an aura cap of `cap`: the cap
---itself while `stack_strip_segmented` is on (the default, and today's
---behaviour), otherwise 1 — a single host that the pip tap fills to
---`stacks / cap`, which is the continuous-bar form. Shared by every stack strip:
---`stackPipSpec` and the six `refreshResourceCount` branches must agree on the
---count or the hosts and the tap would be built to different lengths.
---A plain profile read and one comparison, no allocation — this sits on the
---Refresh path.
---@param cap integer
---@return integer
stackTap.segmentsFor = function(cap)
    return getSettings().stack_strip_segmented ~= false and cap or 1
end

---Returns the current max Arcane Salvo stacks: 20 base, 25 with the Sunfury
---hero talent Spellfire Salvo. Same shape as `ssState.getMaxStacks` — Arcane
---Salvo owns no state table of its own (no watcher, no cached count), so it
---hangs off the shared stack-strip table rather than adding a file-scope local
---to a main chunk already near Lua's 200-local ceiling.
---
---Nothing re-registers on the talent flip: `refreshResourceCount` re-resolves
---the cap on every pass, `talentEventFrame`'s PLAYER_TALENT_UPDATE drives a
---Refresh even when the primary power type is unchanged, and `ensurePips`
---guards on `maxApplications` as well as the segment count, so the pip set is
---released and rebuilt at the new cap on the first writable pass.
---@return integer
stackTap.arcaneSalvoMax = function()
    return IsPlayerSpell(SRC.SPELLFIRE_SALVO_TALENT_ID)
        and SRC.ARCANE_SALVO_MAX_SPELLFIRE or SRC.ARCANE_SALVO_MAX_BASE
end

---Returns the max nearby Soul Fragment stacks for the current Demon Hunter spec:
---20 on Havoc and Vengeance, 15 on Devourer. Spec-selected, NOT selected from
---whichever of the two auras is present — the stack count and the aura data are
---both secret, so "which one is up" is not readable. Devourer's 15 is the sole
---special case; Havoc and Vengeance share the heal-variant aura and its cap.
---
---Same placement rationale as `stackTap.arcaneSalvoMax`: this resource caches
---nothing (no watcher, no count), so it hangs off the shared stack-strip table
---rather than spending one of the main chunk's ~200 locals.
---@return integer
stackTap.nearbySoulsMax = function()
    return C_SpecializationInfo.GetSpecialization() == 3
        and SRC.NEARBY_SOULS_MAX_DEVOURER or SRC.NEARBY_SOULS_MAX
end

---Returns the Art of the Glaive threshold for the current Demon Hunter spec:
---6 on Havoc, 20 on Vengeance and Devourer. Spec-selected rather than read from
---the aura, for the same reason as `stackTap.nearbySoulsMax` -- one aura serves
---all three specs and its stack count is secret, so the spec index is the only
---readable discriminator. `SpellAuraOptions.CumulativeAura` is 80 and is NOT
---this number; see the SRC.AOTG_* comment block.
---
---Same placement rationale as `stackTap.arcaneSalvoMax`: no state table of its
---own, so it hangs off the shared stack-strip table rather than spending one of
---the main chunk's ~200 locals.
---@return integer
stackTap.artOfGlaiveMax = function()
    return C_SpecializationInfo.GetSpecialization() == 1
        and SRC.AOTG_MAX_HAVOC or SRC.AOTG_MAX
end

---Tap key, aura IDs, rendered segment count and aura cap for whichever stack
---strip is active in the CURRENT row, or nil when that row's resource is
---neither. Segment count and cap are the same number while segmentation is on
---and diverge (1 vs the cap) when it is off, which is why both are returned:
---the count sizes the strip, the cap is what the engine scales the fill to. The
---key is row-scoped (`tapKeyForRow`) so two rows can never share one pip set;
---row 1 still yields the bare `"sweepingstrikes"` / `"teachings"`. The ID maps
---are file-scope constants and the keys are memoized, so this stays
---allocation-free on the Refresh path.
---@return string?, table<number, boolean>?, integer?, integer?, string?, string?
stackPipSpec = function()
    local strip = STACK_STRIPS[playerPowerType]
    if not strip then return end
    local cap = strip.cap()
    return tapKeyForRow(strip.base, rowIndex), strip.auraIDs,
        stackTap.segmentsFor(cap), cap, strip.unit, strip.filter
end

---Applies the value-font profile to the bound stack-count FontString. The
---profile's own anchor is re-applied here rather than through ApplyFontProfile's
---anchor branch so both halves stay in one place.
---
---The anchor target is the ROW, not the component frame: a stack strip can sit
---at row 2 (Wild Imps beside Soul Shards), and a component-frame anchor would
---put its number between the two rows instead of on its own. With one row the
---row fills the component frame exactly, so the single-row case is unchanged.
---`stackTap` is still a singleton and this runs under `withRow`, so it styles
---whichever strip most recently claimed the readout. The FontString itself is no
---longer shared, though: each strip's count rides its own pip container
---(`ensurePips`' `wantCount` slot) and is therefore row-scoped by `tapKeyForRow`,
---so a second readout-bearing strip would render its own number in the right place
---rather than repeating the first strip's. What a second one still needs is the
---FONT pass keyed by row — `stackTap.rowIndex` records one owner, so only that row
---re-anchors. `noReadout` remains the deliberate suppression, for the one pairing
---that can occur (Art of the Glaive beside the DH nearby Soul Fragments strip)
---and for Unbound Flame, whose number was simply not wanted.
---
---Writable only while auras are non-secret — a blocked pass raises fontDirty,
---because font passes only run on config changes and would otherwise never
---converge.
---Shows or hides the bound count FontString.
---
---The FontString now rides the strip's OWN pip container (`ensurePips`' `wantCount`
---slot), which is parented to `resourcesFrame`, so hiding that container or the
---component does reach it. This stays as the explicit path because the readout is
---suppressed on its own in one case the container's visibility does not cover:
---`noReadout`, where the pips are wanted and the number is not.
---
---Historical note, since it explains why this used to be load-bearing: the FS lived
---on the shared `CUE_SR_AuraTap` container on `UIParent`, which `releaseRow`,
---`hideStackPips` and `resourcesFrame:Hide()` all missed -- unticking a strip's
---setting while its aura was up left the number rendering at the released row's last
---position. An older comment before THAT claimed the engine's own visibility covered
---it because the aura "cannot be up on a spec that does not have it", which reasons
---about SPECS while the opt-in strips are scoped by SETTING.
---
---Same contract as `reapFc.tapStacks:SetShown` -- a bound object, so the write
---only lands while auras are non-secret and a mid-combat toggle converges on the
---first writable tick.
---@param shown boolean
stackTap.setShown = function(shown)
    if stackTap.text and not auraTap.blocked() then
        stackTap.text:SetShown(shown)
    end
end

local function applyStackTapFont()
    local fs = stackTap.text
    if not fs or not rowFrame then return end
    if auraTap.blocked() then
        stackTap.fontDirty = true
        return
    end
    stackTap.fontDirty = false
    local valueFont = getSettings().value_font
    local pt, x, y = "CENTER", 0, 0
    if valueFont then
        local p = {}
        for k, v in pairs(valueFont) do p[k] = v end
        p.anchor_point = nil
        private.Util.ApplyFontProfile(fs, p, rowFrame)
        pt = valueFont.anchor_point or pt
        x = valueFont.offset_x or 0
        y = valueFont.offset_y or 0
    end
    fs:ClearAllPoints()
    fs:SetPoint(pt, rowFrame, pt, x, y)
    fs:SetJustifyH("CENTER")
end

---Converges the active stack strip: builds the pip tap and the count text on the
---first writable pass, then shows them. Idempotent and self-gating, so Refresh
---re-invokes it every pass; the build guards keep the hot path free of closure
---allocation. The addon-owned valueText is hidden once the bound FS exists —
---it could only ever show a number we can read, and we deliberately no longer
---read one.
local function updateStackPips()
    if activeResourceCount == 0 or not resourcesFrame then return end
    local key, ids, n, cap, unit, filter = stackPipSpec()
    if not key then return end
    local set = auraTap.pipSets[key]
    -- Captured rather than read inside the closure: the closure runs during
    -- ensurePips' build loop, and reading playerPowerType there would tie the pip
    -- colors to whichever row happened to be aimed at.
    local base = STACK_STRIPS[playerPowerType].base
    -- Thresholds need per-pip slices. With segmentation off `n` is 1 — one bar
    -- spanning the whole cap — so a threshold would flatly recolor the entire strip
    -- rather than its top end. Left on the flat color instead.
    local segmented = n > 1
    -- Captured alongside `base` for the same reason: read inside the build closure it
    -- would follow whichever row is aimed at rather than the one being built.
    local isPrimary = rowIndex == 1 and activeResourceTypes.hasPrimary
    local sig = segmented and stackThresholdSig(base, isPrimary) or 0
    -- Threshold colors are baked in at build time, so an edit needs a rebuild that
    -- the count/cap guard below would not ask for. Stamping an impossible `n` routes
    -- it through ensurePips' own rebuild branch, which disables and hides the
    -- outgoing container — clearing the pipSets entry here instead would strand a
    -- shown container on screen.
    if set and set.thresholdSig ~= sig then set.n = -1 end
    -- The writability test is duplicated from ensurePips so a pass that cannot
    -- build allocates nothing — Refresh runs hundreds of times a second in
    -- combat, and the closure below would be built on every one of them. The
    -- cap is compared as well as the count, for the reason ensurePips' own guard
    -- gives: with segmentation off `n` never moves off 1 while the cap still can.
    if (not set or set.n ~= n or set.maxApplications ~= cap)
        and not (InCombatLockdown() or auraTap.blocked()) then
        local texture = getSettings().texture
        -- Same resolution order as applyColors, which converges these later.
        local r, g, b, a = getCustomResourceColor()
        if not r then r, g, b, a = getResourceColor() end
        -- Resolved HERE, not in the closure: the closure is `initializeFrame`, which
        -- runs in the restricted pre-bind context, and it runs once per pip. Doing the
        -- spec/profile lookup inside would repeat it n times in the one context whose
        -- rules are least worth testing against. Allocates only for pips a threshold
        -- actually claims, and only on a build, which is rare by construction.
        local pipColors
        if segmented then
            for i = 1, n do
                local tr, tg, tb, ta = stackThresholdColor(base, isPrimary, i)
                if tr then
                    pipColors = pipColors or {}
                    pipColors[i] = { tr, tg, tb, ta }
                end
            end
        end
        local built = auraTap.ensurePips(key, ids, n, resourcesFrame, function(bar, i)
            applyPipColor(bar, pipColors and pipColors[i], texture, r, g, b, a)
        end, unit, filter, cap, not STACK_STRIPS[playerPowerType].noReadout)
        -- A fresh set has no bar geometry yet and layoutBars is what supplies
        -- it, so run one now rather than leaving the strip blank until the next
        -- resize. layoutBars never builds, so this cannot re-enter.
        -- A build that could not run returns the SAME set back, so this also
        -- distinguishes "rebuilt" from "declined": only a real build gets the
        -- signature stamped, leaving a declined pass still asking for one. Its
        -- `n` stays at the -1 stamped above, so the guard re-fires next pass.
        if built and built ~= set then
            layoutBars()
            built.thresholdSig = sig
        end
        set = built
    end
    if set then auraTap.setPipsShown(key, true) end
    -- The animated border is independent of the pips: it spans the whole strip, so it
    -- works with segmentation off too, and it has its own signature guard rather than
    -- riding the pip rebuild. `ensureBorder` self-gates on writability and stamps the
    -- signature only when it actually ran, so a declined pass retries next tick.
    local wantBorder = getSettings().stack_strip_threshold_glow
    local borderSig = wantBorder and stackThresholdSig(base, isPrimary) or 0
    if auraTap.borderSigs[key] ~= borderSig then
        local runs = wantBorder and stackThresholdRuns(base, isPrimary, cap) or nil
        auraTap.ensureBorder(key, ids, runs, cap, resourcesFrame, unit, filter, borderSig)
        -- Gate the relayout on the SIGNATURE, not on the return value. A pass declined
        -- for combat or secrecy hands the OLD set straight back, so testing the return
        -- fired a full layoutBars on every Refresh for as long as the signature stayed
        -- unmet -- the relayout storm `.context/performance.md` catalogues. Only a pass
        -- that really ran stamps the signature.
        if auraTap.borderSigs[key] == borderSig and auraTap.borderSets[key] then
            -- Same reason ensurePips gets one: a fresh set has no geometry until
            -- layoutBars runs, and layoutBars never builds, so this cannot re-enter.
            layoutBars()
        end
    end
    auraTap.setBorderShown(key, true)
    -- Every pass, not only the pass that built the set. `hideRowOverlays`
    -- clears `tapKey` on release while `setPipsShown` leaves the set itself in
    -- `auraTap.pipSets`, so a release-then-re-add cycle (toggle off/on, row
    -- count change, spec swap out and back) finds the set already at the right
    -- `n`, skips the build branch entirely, and would otherwise re-show a
    -- container that is still `SetEnabled(true)` with a nil `tapKey` -- i.e.
    -- with both the target watcher and the friendly-target gate dead.
    -- Allocation-free and idempotent: `SetEnabled`/`SetUnit` short-circuit on
    -- an unchanged value (`Blizzard_AuraContainer.lua:28/40`).
    if set and unit == "target" then
        shatterState.tapKey = key
        shatterState.syncTarget()
    end
    -- Two rows set `noReadout`. Art of the Glaive can be up alongside the nearby
    -- Soul Fragments strip on every DH spec, and it is a threshold
    -- counter whose pips already answer "how close to 6 / 20". Unbound Flame's
    -- number disagreed with its own pips in play (1 against 4 casts) and was not
    -- wanted anyway.
    if STACK_STRIPS[playerPowerType].noReadout then return end
    -- The FontString belongs to the pip set, so it is row-scoped for free and is
    -- rebuilt with the set. Re-point on identity change rather than on `not
    -- stackTap.text`: a rebuild (cap flip, threshold edit) hands back a NEW
    -- FontString, and a nil-guard would leave stackTap pointing at the destroyed
    -- one -- the number would freeze at its last value and never re-font.
    local fs = set and set.countText
    if not fs then return end
    if stackTap.text ~= fs then
        stackTap.text = fs
        applyStackTapFont()
    elseif stackTap.fontDirty then
        applyStackTapFont()
    end
    -- This row owns the readout. The stamp is what lets the fonts pass re-anchor
    -- from the owning row only, and `hideStackPips` / `releaseRow` hide it.
    stackTap.rowIndex = rowIndex
    -- Show Value governs this readout too. It is gated here rather than through
    -- `ensurePips`' `wantCount`, which only takes effect in the build branch that
    -- the reuse guard skips -- folding the setting in there would make the toggle
    -- wait for a rebuild. `setShown` writes a FontString that is already bound.
    stackTap.setShown(getSettings().show_value == true)
    if stackTap.text and rowFrame and rowFrame.valueText then rowFrame.valueText:Hide() end
end

---The rect pip i covers: the (permanently empty) host segment's fill bar, so the
---tap sits exactly where the old per-segment fill did.
---@param i integer
---@return StatusBar?
local function stackPipHost(i)
    local rf = resourceFrames[i]
    return rf and rf.bar
end

---Blanks the host segments a stack strip is about to overlay. The fill is the
---pip tap's now, so the hosts stay empty and nothing stale shows through when
---the aura drops and the engine hides the taps. Same contract as the Ignore Pain
---host in refreshResourceCount.
---@param n integer
local function emptyStackHosts(n)
    for i = 1, n do
        local rf = resourceFrames[i]
        if rf and rf.bar then
            rf.bar:SetMinMaxValues(0, 1)
            rf.bar:SetValue(0)
        end
    end
end

---Layout tail for the active stack strip. The pip tap overlays the host bars, so
---it re-anchors whenever layoutBars re-sizes them.
layoutStackPips = function(pipW, pipH, vertical)
    local key = stackPipSpec()
    if not key then return end
    auraTap.layoutPips(key, stackPipHost, pipW, pipH, vertical)
    -- The border spans the whole strip rather than a pip, so it takes the row frame
    -- rather than a per-pip host. Same re-anchor-on-resize contract as the pips. The
    -- segment pitch goes with it so its boundaries land on real segment edges — see
    -- layoutBorder's `edgeAt`.
    local _, _, n = stackPipSpec()
    auraTap.layoutBorder(key, rowFrame, vertical, pipW, pipH,
        getSettings().bar_spacing or SRC.DEFAULT_BAR_GAP, n)
end

---Hides every stack strip in every row. The tap carries the whole pip readout,
---so hiding its container takes it with it; the next updateStackPips pass
---re-shows it. The bound count FontString needs its own hide — see
---`stackTap.setShown` for why the engine's visibility does not cover it.
local function hideStackPips()
    for i = 1, #rowFrames do
        for _, strip in pairs(STACK_STRIPS) do
            local rowKey = tapKeyForRow(strip.base, i)
            auraTap.setPipsShown(rowKey, false)
            auraTap.setBorderShown(rowKey, false)
        end
    end
    -- The bound count FontString is not reachable from any row: its container is
    -- on UIParent. See stackTap.setShown.
    stackTap.rowIndex = nil
    stackTap.setShown(false)
end

-- ── Fury Warrior Whirlwind charge functions ──────────────────────────────────

---Updates the discrete WW charge bar display (same pattern as Vengeance Soul Fragments).
wwState.updateChargeDisplay = function()
    if activeResourceCount == 0 then return end
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(wwState.charges, barInterpolation)
    end
    applyThresholdColors()
    updateValueText()
end

---OnUpdate callback that expires WW charges after SRC.WW_DURATION seconds.
wwState.onUpdate = function()
    if wwState.charges > 0 and wwState.expiresAt then
        if GetTime() >= wwState.expiresAt then
            wwState.charges = 0
            wwState.expiresAt = nil
            wwState.updateChargeDisplay()
            if resourcesFrame then
                resourcesFrame:SetScript("OnUpdate", nil)
            end
        end
    end
end

---Returns true if any Bladestorm aura is active on the player.
local function isBladestormActive()
    for spellID in pairs(SRC.bladestormAuraIDs) do
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
            return true
        end
    end
    return false
end

---Creates and registers the UNIT_SPELLCAST_SUCCEEDED event frame for WW charge tracking.
local function registerWWEvents()
    if not wwState.eventFrame then
        wwState.eventFrame = CreateFrame("Frame")
        wwState.eventFrame:SetScript("OnEvent", function(_, _, unit, castGUID, spellID)
            if unit ~= "player" then return end
            if not IsPlayerSpell(SRC.WW_TALENT_ID) then return end
            if not (SRC.wwBuilderSpells[spellID] or SRC.wwSpenderSpells[spellID]
                or SRC.bladestormAuraIDs[spellID]) then
                return
            end

            -- Deduplicate by castGUID. A duplicate event arrives straight after
            -- its original, so the last GUID is enough; a table of every GUID
            -- grew by one entry per builder/spender for the whole session.
            if castGUID and castGUID == wwState.lastCastGUID then return end
            wwState.lastCastGUID = castGUID

            -- Unhinged: detect Bladestorm casts to block consumption
            if IsPlayerSpell(386628) and SRC.bladestormAuraIDs[spellID] then
                wwState.noConsumeUntil = GetTime() + 2
            end

            -- Builder: set charges to max
            if SRC.wwBuilderSpells[spellID] then
                -- Thunder Clap/Blast require Crackling Thunder or Crashing Thunder talent
                if (spellID == 6343 or spellID == 435222)
                    and not IsPlayerSpell(203201)
                    and not IsPlayerSpell(436707) then
                    return
                end
                wwState.charges = SRC.WW_MAX_CHARGES
                wwState.expiresAt = GetTime() + SRC.WW_DURATION
                wwState.updateChargeDisplay()
                if resourcesFrame then
                    resourcesFrame:SetScript("OnUpdate", wwState.onUpdate)
                end
                return
            end

            -- Spender: consume one charge
            if SRC.wwSpenderSpells[spellID] then
                if wwState.charges <= 0 then return end
                -- Unhinged blocks Bloodthirst/Bloodbath during Bladestorm
                if spellID == 23881 or spellID == 335096 then
                    if GetTime() < wwState.noConsumeUntil
                        or (IsPlayerSpell(386628) and isBladestormActive()) then
                        return
                    end
                end
                wwState.charges = math.max(0, wwState.charges - 1)
                if wwState.charges > 0 then
                    wwState.expiresAt = GetTime() + SRC.WW_DURATION
                else
                    wwState.expiresAt = nil
                    if resourcesFrame then
                        resourcesFrame:SetScript("OnUpdate", nil)
                    end
                end
                wwState.updateChargeDisplay()
                return
            end
        end)
    end
    wwState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

---Unregisters WW charge events and resets tracking state.
local function unregisterWWEvents()
    if wwState.eventFrame then
        wwState.eventFrame:UnregisterAllEvents()
    end
    wwState.charges = 0
    wwState.expiresAt = nil
    wwState.lastCastGUID = nil
    wwState.noConsumeUntil = 0
end

-- ── Survival Hunter Tip of the Spear functions ──────────────────────────────

---Updates the discrete TotS charge bar display (same offset MinMax pattern as WW charges).
totsState.updateChargeDisplay = function()
    if activeResourceCount == 0 then return end
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(totsState.charges, barInterpolation)
    end
    applyThresholdColors()
    updateValueText()
end

---Creates and registers the UNIT_AURA event frame for Tip of the Spear stack tracking.
local function registerTotsEvents()
    if not totsState.eventFrame then
        totsState.eventFrame = CreateFrame("Frame")
        totsState.eventFrame:SetScript("OnEvent", function()
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(SRC.TOTS_AURA_ID)
            local newCharges = aura and aura.applications or 0
            if newCharges ~= totsState.charges then
                totsState.charges = newCharges
                totsState.updateChargeDisplay()
            end
        end)
    end
    totsState.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
end

---Unregisters TotS aura events and resets tracking state.
local function unregisterTotsEvents()
    if totsState.eventFrame then
        totsState.eventFrame:UnregisterAllEvents()
    end
    totsState.charges = 0
end

-- ── Frost Mage Icicles functions ─────────────────────────────────────────
-- All functions stored on iciclesState table to conserve file-level local slots.

---Creates or returns the BackdropTemplate glow border frame for full Icicle stacks.
---Same pattern as getOrCreateSwingOverflowBorder (Paladin swing timer).
iciclesState.getOrCreateGlow = function()
    if iciclesState.glowFrame then return iciclesState.glowFrame end

    local f = CreateFrame("Frame", nil, resourcesFrame, "BackdropTemplate")
    private.Pixel.SetPoint(f, "TOPLEFT", resourcesFrame, "TOPLEFT", 0, 0)
    private.Pixel.SetPoint(f, "BOTTOMRIGHT", resourcesFrame, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel(resourcesFrame:GetFrameLevel() + 2)

    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })

    -- Pulse animation: bounce between 0.5 and 1 alpha
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    ag:SetToFinalAlpha(true)
    local fade = ag:CreateAnimation("Alpha")
    fade:SetDuration(0.8)
    fade:SetFromAlpha(0.5)
    fade:SetToAlpha(1)
    fade:SetSmoothing("IN_OUT")
    fade:SetOrder(1)
    ag:SetScript("OnPlay", function() f:Show() end)
    ag:SetScript("OnStop", function() f:Hide() end)
    f.pulseAnim = ag

    f:Hide()
    iciclesState.glowFrame = f
    return f
end

---Shows the pulsing glow border for full Icicle stacks.
iciclesState.showGlow = function()
    if iciclesState.glowing then return end
    iciclesState.glowing = true
    local glow = iciclesState.getOrCreateGlow()
    local c = getSettings().frost_icicles_color
    glow:SetBackdropBorderColor(private.Util.Color(c))
    glow.pulseAnim:Play()
end

---Hides the pulsing glow border and resets glow state.
iciclesState.hideGlow = function()
    if not iciclesState.glowing then return end
    iciclesState.glowing = false
    if iciclesState.glowFrame and iciclesState.glowFrame.pulseAnim:IsPlaying() then
        iciclesState.glowFrame.pulseAnim:Stop()
    end
    if iciclesState.glowFrame then
        iciclesState.glowFrame:Hide()
    end
end

---Updates the Icicles bar display. Full bars get SetValue(1), the in-progress bar
---uses SetTimerDuration for engine-driven fill, and empty bars get SetValue(0).
---Re-applies SetMinMaxValues + SetTimerDuration every call to keep bars in sync.
---Manages glow visibility based on whether stacks are at maximum.
iciclesState.updateDisplay = function()
    if activeResourceCount == 0 then return end
    for i = 1, activeResourceCount do
        local bar = resourceFrames[i].bar
        bar:SetMinMaxValues(0, 1)
        if i <= iciclesState.count then
            bar:SetValue(1)
        elseif i == iciclesState.count + 1 and iciclesState.count < SRC.ICICLES_MAX and iciclesState.durationObj then
            bar:SetValue(0)
            bar:SetTimerDuration(iciclesState.durationObj, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
        else
            bar:SetValue(0)
        end
    end
    -- Glow at full stacks
    if iciclesState.count >= SRC.ICICLES_MAX then
        iciclesState.showGlow()
    else
        iciclesState.hideGlow()
    end
    applyThresholdColors()
    updateValueText()
end

---Reads the current Icicles aura, updates state, and refreshes the display.
---Called from the UNIT_AURA event handler and during Refresh.
---Count is initialized to -1 so the first call always detects a change.
iciclesState.refresh = function()
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(SRC.ICICLES_AURA_ID)
    local newCount = aura and aura.applications or 0

    if newCount ~= iciclesState.count then
        local oldCount = iciclesState.count
        local now = GetTime()
        -- Sample the realized interval on clean +1 gains. Reject deltas
        -- outside a sane window so a stale anchor from before a haste
        -- shift, combat gap, or GS reset does not poison the cache.
        if newCount == oldCount + 1 and oldCount >= 0 then
            local anchor = iciclesState.lastStackGainTime
            if anchor then
                local delta = now - anchor
                if delta >= 0.5 and delta <= SRC.ICICLES_BASE_DURATION * 2 then
                    iciclesState.lastHastedDuration = delta
                end
            end
            iciclesState.lastStackGainTime = now
        else
            iciclesState.lastStackGainTime = nil
        end
        iciclesState.count = newCount

        -- Configure the fill timer for the next bar (or the hidden 6th at max stacks).
        -- At max stacks the passive timer keeps running in the background; when GS
        -- consumes all icicles, bar 1 inherits this timer showing correct fill progress.
        if not iciclesState.durationObj then
            iciclesState.durationObj = C_DurationUtil.CreateDuration()
        end
        local hastedDuration = iciclesState.getHastedDuration()
        if oldCount == -1 then
            -- First refresh after login/reload: assume in-progress icicle is about to complete
            iciclesState.durationObj:SetTimeFromStart(now - hastedDuration, hastedDuration)
        else
            iciclesState.durationObj:SetTimeFromStart(now, hastedDuration)
        end
    end

    -- Always re-apply display state — external callers (refreshResourceCount)
    -- may have called SetMinMaxValues on all bars, killing any running timer.
    iciclesState.updateDisplay()
end

---Creates and registers event frames for Icicles stack tracking.
---UNIT_AURA tracks stack count changes; UNIT_SPELLCAST_SUCCEEDED catches Glacial Spike
---casts to immediately reset to count 0 and restart the fill timer.
iciclesState.registerEvents = function()
    if not iciclesState.eventFrame then
        iciclesState.eventFrame = CreateFrame("Frame")
        iciclesState.eventFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                if spellID == SRC.GLACIAL_SPIKE_SPELL then
                    -- Set count to 0; keep durationObj — it holds the hidden 6th
                    -- timer that was running at 5/5. Bar 1 inherits it, showing
                    -- the correct fill progress for the next icicle.
                    iciclesState.count = 0
                    iciclesState.lastStackGainTime = nil
                    iciclesState.updateDisplay()
                end
                return
            end
            if event == "UNIT_AURA" then
                iciclesState.refresh()
                return
            end
            -- Any generation-rate-shift event invalidates the observed-interval
            -- cache (haste changes on talent/spec/gear swaps; the unhasted base
            -- itself halves out of combat). Next clean stack gain reseeds it.
            iciclesState.lastHastedDuration = nil
            iciclesState.lastStackGainTime = nil
        end)
    end
    iciclesState.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    iciclesState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    iciclesState.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    iciclesState.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    iciclesState.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    iciclesState.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    iciclesState.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
end

---Unregisters Icicles aura events and resets tracking state.
iciclesState.unregisterEvents = function()
    if iciclesState.eventFrame then
        iciclesState.eventFrame:UnregisterAllEvents()
    end
    iciclesState.count = -1
    iciclesState.lastHastedDuration = nil
    iciclesState.lastStackGainTime = nil
    iciclesState.hideGlow()
end

-- ── Guardian Druid Ironfur functions ─────────────────────────────────────────

---Returns or creates a tick mark texture at the given pool index.
---Tick marks are thin vertical lines overlaid on the single Ironfur bar.
---@param index integer 1-based pool index
---@return Texture
ironfurState.getOrCreateTick = function(index)
    local tick = ironfurState.ticks[index]
    if tick then return tick end
    local bar = resourceFrames[1].bar
    tick = bar:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(1, 1, 1, 0.8)
    tick:SetWidth(2)
    tick:SetPoint("TOP", bar, "TOP", 0, 0)
    tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    tick:Hide()
    ironfurState.ticks[index] = tick
    return tick
end

---Applies the engine-driven bar drain and positions all tick marks.
---Called on new cast and on stack expiry.
ironfurState.applyBarAndTicks = function()
    local instances = ironfurState.instances
    local count = #instances

    if count == 0 then
        if resourceFrames[1] then
            resourceFrames[1].bar:SetValue(0)
        end
        for _, tick in ipairs(ironfurState.ticks) do
            tick:Hide()
        end
        if resourcesFrame then
            resourcesFrame:SetScript("OnUpdate", nil)
        end
        ironfurState.lastCount = count
        updateValueText()
        return
    end

    -- Anchor instance = latest expiresAt (drives bar drain).
    -- With talent modifiers, the newest cast may not be the longest-remaining.
    if not ironfurState.durationObj then
        ironfurState.durationObj = C_DurationUtil.CreateDuration()
    end
    local anchor = instances[1]
    for i = 2, count do
        if instances[i].expiresAt > anchor.expiresAt then
            anchor = instances[i]
        end
    end
    ironfurState.durationObj:SetTimeFromStart(anchor.expiresAt - anchor.duration, anchor.duration)

    if resourceFrames[1] then
        local bar = resourceFrames[1].bar
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetTimerDuration(ironfurState.durationObj, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
    end

    -- Position tick marks at static fractions for non-anchor instances.
    -- The bar drains from 1 (full, right) to 0 (empty, left). At the moment another
    -- stack expires, the bar value will be (anchorExpiry - otherExpiry) / anchorDuration.
    -- That fraction * barWidth gives the x-offset from the left edge.
    local barWidth = resourceFrames[1] and resourceFrames[1].bar:GetWidth() or 0
    local tickIdx = 0
    for i = 1, count do
        if instances[i] ~= anchor then
            tickIdx = tickIdx + 1
            local tick = ironfurState.getOrCreateTick(tickIdx)
            local frac = (anchor.expiresAt - instances[i].expiresAt) / anchor.duration
            if frac < 0 then frac = 0 end
            if frac > 1 then frac = 1 end
            local scale = resourceFrames[1].bar:GetEffectiveScale()
            local xOffset = PixelUtil.GetNearestPixelSize(frac * barWidth, scale)
            tick:ClearAllPoints()
            tick:SetPoint("TOP", resourceFrames[1].bar, "TOPLEFT", xOffset, 0)
            tick:SetPoint("BOTTOM", resourceFrames[1].bar, "BOTTOMLEFT", xOffset, 0)
            tick:Show()
        end
    end

    -- Hide unused ticks
    for i = tickIdx + 1, #ironfurState.ticks do
        ironfurState.ticks[i]:Hide()
    end

    if count ~= ironfurState.lastCount then
        ironfurState.lastCount = count
        updateValueText()
    end
end

---Refreshes cached talent state for Ursoc's Endurance and Guardian of Elune.
ironfurState.updateTalents = function()
    ironfurState.ursocKnown = IsPlayerSpell(SRC.URSOCS_ENDURANCE_ID)
    ironfurState.goeKnown = IsPlayerSpell(SRC.GOE_TALENT_ID)
    ironfurState.goeActive = false
end

---Adds a new Ironfur instance from a successful cast and refreshes the display.
ironfurState.addInstance = function()
    local now = GetTime()
    local dur = SRC.IRONFUR_BASE_DURATION
    if ironfurState.ursocKnown then
        dur = dur + SRC.URSOCS_BONUS
    end
    if ironfurState.goeActive then
        dur = dur + SRC.GOE_BONUS
        ironfurState.goeActive = false
    end
    ironfurState.instances[#ironfurState.instances + 1] = { expiresAt = now + dur, duration = dur }

    ironfurState.applyBarAndTicks()

    -- Ensure OnUpdate is running for expiry detection
    if resourcesFrame then
        resourcesFrame:SetScript("OnUpdate", ironfurState.onUpdate)
    end
end

---OnUpdate handler — checks for expired instances only. Tick positions are static.
---@type number
local ironfurThrottle = 0
ironfurState.onUpdate = function(_, elapsed)
    ironfurThrottle = ironfurThrottle + elapsed
    if ironfurThrottle < 0.2 then return end
    ironfurThrottle = 0

    local now = GetTime()
    local instances = ironfurState.instances
    local expired = false
    -- Scan every instance: the list is cast-ordered, not expiry-ordered, so a
    -- shorter cast behind a Guardian of Elune one can expire first.
    for i = #instances, 1, -1 do
        if now >= instances[i].expiresAt then
            table.remove(instances, i)
            expired = true
        end
    end
    if expired then
        ironfurState.applyBarAndTicks()
    end
end

---Creates and registers the event frame for Ironfur cast tracking.
ironfurState.registerEvents = function()
    if not ironfurState.eventFrame then
        ironfurState.eventFrame = CreateFrame("Frame")
        ironfurState.eventFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                if spellID == SRC.IRONFUR_SPELL_ID then
                    ironfurState.addInstance()
                elseif spellID == SRC.MANGLE_SPELL_ID then
                    if ironfurState.goeKnown then
                        ironfurState.goeActive = true
                    end
                elseif spellID == SRC.FR_SPELL_ID then
                    ironfurState.goeActive = false
                end
            else -- PLAYER_TALENT_UPDATE / TRAIT_CONFIG_UPDATED
                ironfurState.updateTalents()
            end
        end)
    end
    ironfurState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ironfurState.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    ironfurState.eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    ironfurState.updateTalents()
end

---Unregisters Ironfur events and resets tracking state.
ironfurState.unregisterEvents = function()
    if ironfurState.eventFrame then
        ironfurState.eventFrame:UnregisterAllEvents()
    end
    wipe(ironfurState.instances)
    ironfurState.lastCount = 0
    ironfurState.goeActive = false
    for _, tick in ipairs(ironfurState.ticks) do
        tick:Hide()
    end
    if resourcesFrame then
        resourcesFrame:SetScript("OnUpdate", nil)
    end
end

-- ── Enhancement Shaman Maelstrom Weapon functions ───────────────────────────

---Updates the discrete Maelstrom Weapon charge bar display (same offset MinMax pattern as TotS/WW).
---When the threshold color option is enabled, segments at or above the instant-cast threshold (5+)
---use a lighter highlight color when filled.
mwState.updateChargeDisplay = function()
    if activeResourceCount == 0 then return end
    if playerPowerType ~= SRC.MW_CHARGES_ENHANCEMENT then return end
    local settings = getSettings()
    local useThreshold = settings.enhancement_mw_threshold
    local thresholdColor = useThreshold and settings.enhancement_mw_threshold_color
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(mwState.charges, barInterpolation)
        if useThreshold and i >= SRC.MW_INSTANT_THRESHOLD and mwState.charges >= i then
            resourceFrames[i].bar:SetStatusBarColor(thresholdColor[1], thresholdColor[2], thresholdColor[3], thresholdColor[4] or 1)
        end
    end
    applyThresholdColors()
    updateValueText()
end

---Creates and registers the UNIT_AURA event frame for Maelstrom Weapon stack tracking.
local function registerMwEvents()
    -- Kept when the talent reads unknown: a UNIT_AURA can land between a
    -- respec and the PLAYER_TALENT_UPDATE that resolves the strip away.
    mwState.variant = getMwVariant() or mwState.variant
    if not mwState.eventFrame then
        mwState.eventFrame = CreateFrame("Frame")
        mwState.eventFrame:SetScript("OnEvent", function()
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(mwState.variant.aura)
            local newCharges = aura and aura.applications or 0
            if newCharges ~= mwState.charges then
                mwState.charges = newCharges
                mwState.updateChargeDisplay()
            end
        end)
    end
    mwState.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
end

---Unregisters Maelstrom Weapon aura events and resets tracking state.
local function unregisterMwEvents()
    if mwState.eventFrame then
        mwState.eventFrame:UnregisterAllEvents()
    end
    mwState.charges = 0
end

-- ── Rogue Coup de Grâce pip functions ────────────────────────────────────────
--
-- Same engine-driven shape as the stack strips above: four slot-bound
-- StatusBars (auraTap.ensurePips, "cdg" key) render the secret Escalating Blade
-- stack count, one slice each. The BuffIcon child scan this replaced returned
-- the count out of combat and a flat 1 ("buff present, count unknown") in it,
-- so the pips under-reported for the whole of every pull.

local CDG_AURA_IDS = { [SRC.CDG_BUFF_ID] = true }

---Returns true when Coup de Grâce pips should be displayed:
---player is a Rogue, the toggle is enabled, and the current power type is ComboPoints.
---No talent check needed — the tap self-hides while the Escalating Blade buff
---(441786) is absent, so an untalented Rogue simply never sees a pip.
local function isCdGEligible()
    return playerPowerType == Enum.PowerType.ComboPoints
        and select(2, UnitClass("player")) == "ROGUE"
        and getSettings().rogue_coup_de_grace
end

---Creates the geometry host for one Coup de Grâce pip: a plain frame marking the
---strip's rect. It draws nothing — the visible fill is the engine-driven bar the
---pip tap anchors over it.
---@param resourceFrame Frame
---@return Frame
local function createCdGPip(resourceFrame)
    local pip = CreateFrame("Frame", nil, resourceFrame)
    pip:SetFrameLevel(resourceFrame:GetFrameLevel() + 2)
    return pip
end

---The rect pip i covers.
---@param i integer
---@return Frame?
local function cdgPipHost(i)
    return cdgState.pips[i]
end

---Positions the Coup de Grâce strips on the first 4 combo point segments and
---re-anchors the pip tap onto them. Horizontal: a thin strip along the bottom
---edge. Vertical: along the left edge. pipW/pipH are one combo segment's size,
---handed down from layoutBars.
cdgState.layoutPips = function(pipW, pipH, vertical)
    local tapKey = tapKeyForRow("cdg", rowIndex)
    if not isCdGEligible() then
        auraTap.setPipsShown(tapKey, false)
        for i = 1, #cdgState.pips do
            cdgState.pips[i]:Hide()
        end
        return
    end

    local thickness = 3
    for i = 1, SRC.CDG_MAX_STACKS do
        if not resourceFrames[i] then break end
        if not cdgState.pips[i] then
            cdgState.pips[i] = createCdGPip(resourceFrames[i])
        end
        local pip = cdgState.pips[i]
        pip:SetParent(resourceFrames[i])
        pip:ClearAllPoints()
        if vertical then
            pip:SetPoint("TOPLEFT", resourceFrames[i], "TOPLEFT", 0, 0)
            pip:SetPoint("BOTTOMLEFT", resourceFrames[i], "BOTTOMLEFT", 0, 0)
            pip:SetWidth(thickness)
        else
            pip:SetPoint("BOTTOMLEFT", resourceFrames[i], "BOTTOMLEFT", 0, 0)
            pip:SetPoint("BOTTOMRIGHT", resourceFrames[i], "BOTTOMRIGHT", 0, 0)
            pip:SetHeight(thickness)
        end
    end

    for i = SRC.CDG_MAX_STACKS + 1, #cdgState.pips do
        cdgState.pips[i]:Hide()
    end

    -- The strip runs along whichever edge the pips were just given, so its
    -- pip-length is the segment's size on that axis and its thickness the other.
    auraTap.layoutPips(tapKey, cdgPipHost,
        vertical and thickness or pipW,
        vertical and pipH or thickness, vertical)
end

---Converges the Coup de Grâce pip tap: builds it on the first writable pass,
---keeps its colour in step with the setting, and shows or hides it with
---eligibility. The stack count is never read — the engine fills the four bound
---bars from the aura itself.
cdgState.updateDisplay = function()
    local tapKey = tapKeyForRow("cdg", rowIndex)
    if not isCdGEligible() then
        auraTap.setPipsShown(tapKey, false)
        for i = 1, #cdgState.pips do
            cdgState.pips[i]:Hide()
        end
        return
    end

    for i = 1, SRC.CDG_MAX_STACKS do
        if cdgState.pips[i] then cdgState.pips[i]:Show() end
    end
    -- Both branches below build a closure, so both are gated on writability
    -- first — updateDisplay runs from every applyColors, i.e. every combat
    -- Refresh, and neither the build nor the restyle can land there anyway.
    if auraTap.blocked() or InCombatLockdown() then
        auraTap.setPipsShown(tapKey, true)
        return
    end
    local color = getSettings().rogue_coup_de_grace_color
    if not auraTap.pipSets[tapKey] then
        local built = auraTap.ensurePips(tapKey, CDG_AURA_IDS, SRC.CDG_MAX_STACKS,
            resourcesFrame, function(bar)
                bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local tex = bar:GetStatusBarTexture()
                if tex then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
            end)
        -- A fresh set has no bar geometry yet; layoutBars supplies it (and the
        -- host strips' own anchors). It never builds, so this cannot re-enter.
        if built then layoutBars() end
    else
        auraTap.stylePips(tapKey, function(bar)
            bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        end)
    end
    auraTap.setPipsShown(tapKey, true)
end

---Hides the Coup de Grâce pips in every row. Nothing to unregister: the tap is
---engine-driven, so the old BuffIcon OnUnitAura hook and the UNIT_AURA fallback
---frame are gone. This is a teardown, so it clears every row's set rather than
---only the current one — a row that stops showing combo points must not leave
---its strip behind.
local function unregisterCdGEvents()
    for i = 1, #rowFrames do
        auraTap.setPipsShown(tapKeyForRow("cdg", i), false)
    end
    for i = 1, #cdgState.pips do
        cdgState.pips[i]:Hide()
    end
end

-- ── Fire Mage Fire Blast charge functions ────────────────────────────────────

---Updates the Fire Blast charge bar display with a single recharge overlay.
---Base bars use offset MinMax so the secret currentCharges auto-clamps each segment full/empty.
---A hidden reference StatusBar (fbRefBar) spans all segments; its SetValue(currentCharges)
---positions the fill right edge at the correct segment boundary. The recharge bar (fbRechargeBar)
---anchors to that edge and uses SetTimerDuration to animate the fill for the recharging segment.
local updateFireBlastCharges = function()
    if activeResourceCount == 0 then return end
    local chargeInfo = C_Spell.GetSpellCharges(SRC.FIRE_BLAST_SPELL_ID)
    if chargeInfo then
        cachedFireBlastCharges = chargeInfo.currentCharges
    end
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(cachedFireBlastCharges, barInterpolation)
    end

    -- Update reference bar value so its fill edge tracks the current charge count
    if fbRefBar then
        fbRefBar:SetValue(cachedFireBlastCharges, barInterpolation)
    end

    -- Recharge overlay
    local duration = C_Spell.GetSpellChargeDuration(SRC.FIRE_BLAST_SPELL_ID)
    if duration and fbRechargeBar then
        fbRechargeBar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
        fbRechargeBar:Show()
    elseif fbRechargeBar then
        fbRechargeBar:Hide()
    end

    -- Tier B threshold fold — re-evaluate on each charge change.
    local tr, tg, tb, ta = getCustomResourceColor()
    if tr then
        applyThresholdColorsSecret(cachedFireBlastCharges, CreateColor(tr, tg, tb, ta or 1))
    end

    updateValueText()
end

---Updates Aimed Shot charge segments, reference bar, recharge overlay, and Lock and Load colors.
local updateAimedShotCharges = function()
    if activeResourceCount == 0 then return end
    local chargeInfo = C_Spell.GetSpellCharges(SRC.AIMED_SHOT_SPELL_ID)
    if chargeInfo then
        cachedAimedShotCharges = chargeInfo.currentCharges
    end
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(cachedAimedShotCharges, barInterpolation)
    end

    if asRefBar then
        asRefBar:SetValue(cachedAimedShotCharges, barInterpolation)
    end

    local duration = C_Spell.GetSpellChargeDuration(SRC.AIMED_SHOT_SPELL_ID)
    if duration and asRechargeBar then
        asRechargeBar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
        asRechargeBar:Show()
    elseif asRechargeBar then
        asRechargeBar:Hide()
    end

    applyLockAndLoadGlow()

    -- Tier B threshold fold — runs after LnL so generic thresholds layer on top.
    local tr, tg, tb, ta = getCustomResourceColor()
    if tr then
        applyThresholdColorsSecret(cachedAimedShotCharges, CreateColor(tr, tg, tb, ta or 1))
    end

    updateValueText()
end

-- ── Paladin Crusading Strikes swing timer functions ─────────────────────────

---Edge thickness for the overflow border (pixels).
local OVERFLOW_EDGE_SIZE = 2

---Creates or returns the overflow border frame, re-parenting if necessary.
---@param parentFrame frame  the max-HP resource segment frame
---@return frame border
local function getOrCreateOverflowBorder(parentFrame)
    if swingState.overflowBorder then
        if swingState.overflowBorder:GetParent() ~= parentFrame then
            swingState.overflowBorder:SetParent(parentFrame)
            swingState.overflowBorder:ClearAllPoints()
            private.Pixel.SetPoint(swingState.overflowBorder, "TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
            private.Pixel.SetPoint(swingState.overflowBorder, "BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", 0, 0)
        end
        return swingState.overflowBorder
    end

    local f = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    private.Pixel.SetPoint(f, "TOPLEFT", parentFrame, "TOPLEFT", 0, 0)
    private.Pixel.SetPoint(f, "BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel(parentFrame:GetFrameLevel() + 2)

    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = OVERFLOW_EDGE_SIZE,
    })

    -- Pulse animation for when the swing completes at max HP
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    ag:SetToFinalAlpha(true)
    local fade = ag:CreateAnimation("Alpha")
    fade:SetDuration(0.8)
    fade:SetFromAlpha(0.5)
    fade:SetToAlpha(1)
    fade:SetSmoothing("IN_OUT")
    fade:SetOrder(1)
    ag:SetScript("OnPlay", function() f:Show() end)
    ag:SetScript("OnStop", function() f:Hide() end)
    f.pulseAnim = ag

    f:Hide()
    swingState.overflowBorder = f
    return f
end

---Hides and resets the overflow border state.
local function hideOverflowBorder()
    if not swingState.overflowBorder then return end
    if swingState.overflowBorder.pulseAnim:IsPlaying() then
        swingState.overflowBorder.pulseAnim:Stop()
    end
    swingState.overflowBorder:Hide()
    swingState.overflowGlowing = false
end

---Returns the color for the swing timer fill bar.
---Uses the profile's custom swing color when enabled, otherwise auto-lightens the resource color.
---@return number r, number g, number b, number a
local function getSwingTimerColor()
    local settings = getSettings()
    if settings.paladin_swing_custom_color then
        local c = settings.paladin_swing_color
        return private.Util.Color(c)
    end
    local r, g, b, a = getResourceColor()
    return math.min(1, r * 1.5), math.min(1, g * 1.5), math.min(1, b * 1.5), a
end

---Walks the class tree once per configID to find the node containing
---SRC.ZEALOTS_FERVOR_ENTRY_ID, then reads activeRank and writes the
---resulting (1 + bonus) multiplier into private.swingZealotsFervorMult.
---Mirrors private.innateMagicMultiplier but caches the resolved value
---rather than returning it, since the formula is consumed every OnUpdate
---frame and we don't want to allocate a NodeInfo table per frame.
---Untalented state and respec-without-this-talent both fall through to 1.0.
swingState.refreshZealotsFervorMult = function()
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        private.swingZealotsFervorMult = 1.0
        return
    end
    local resolved = private.zealotsFervorResolved
    if resolved.configID ~= configID then
        resolved.configID = configID
        resolved.nodeID = nil
        local cfg = C_Traits.GetConfigInfo(configID)
        if cfg and cfg.treeIDs then
            for _, treeID in ipairs(cfg.treeIDs) do
                for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
                    local ni = C_Traits.GetNodeInfo(configID, nodeID)
                    if ni and ni.entryIDs then
                        for _, entryID in ipairs(ni.entryIDs) do
                            if entryID == SRC.ZEALOTS_FERVOR_ENTRY_ID then
                                resolved.nodeID = nodeID
                                break
                            end
                        end
                    end
                    if resolved.nodeID then break end
                end
                if resolved.nodeID then break end
            end
        end
    end
    if not resolved.nodeID then
        private.swingZealotsFervorMult = 1.0
        return
    end
    local nodeInfo = C_Traits.GetNodeInfo(configID, resolved.nodeID)
    local bonus = nodeInfo and SRC.ZEALOTS_FERVOR_BONUS[nodeInfo.activeRank]
    private.swingZealotsFervorMult = bonus and (1.0 + bonus) or 1.0
end

---Samples Redemption's cast time (spellID 7328) and updates private.swingHasteMult.
---Redemption's 10s base cast time isn't modified by talents, buffs, or spec — the realized
---castTime directly reflects current haste. Formula: hasteMult = 10000 / castTime.
---Zealot's Fervor (auto-attack-speed only) is NOT reflected in spell haste, so
---private.swingZealotsFervorMult is applied multiplicatively alongside the haste
---multiplier in the swing-duration formula. Verified against in-game numbers:
---3.6 mainhand × 1.20 (CS) / (1.13 spell haste × 1.40 Zealot rank 2) = 2.731s.
---When the multiplier changes and a swing is in progress, the start anchor is
---shifted so the visible fraction is preserved (only the remaining rate changes),
---avoiding a visual jump on mid-swing haste shifts (Avenging Wrath, procs, Bloodlust).
swingState.refreshHasteMult = function()
    local info = C_Spell.GetSpellInfo(7328)
    if not info then return end
    local castTime = info.castTime
    if not castTime or castTime <= 0 then return end
    local newHasteMult = 10000 / castTime
    if newHasteMult == private.swingHasteMult then return end
    if swingState.startTime and private.cachedMainhandSpeed and private.swingHasteMult then
        local now = GetTime()
        local basePeriod = private.cachedMainhandSpeed * SRC.CRUSADING_STRIKES_PERIOD_FACTOR
        local oldDuration = basePeriod / (private.swingHasteMult * private.swingZealotsFervorMult)
        local fraction = math.min(1, (now - swingState.startTime) / oldDuration)
        local newDuration = basePeriod / (newHasteMult * private.swingZealotsFervorMult)
        swingState.startTime = now - fraction * newDuration
    end
    private.swingHasteMult = newHasteMult
end

---Reads the equipped mainhand weapon's intrinsic base swing speed by scanning
---the tooltip via C_TooltipInfo.GetInventoryItem and updates
---private.cachedMainhandSpeed only when a plausible value is recovered.
---Tooltip data is non-secret intrinsic item data, so this works through
---combat / M+ / mid-fight reloads where UnitAttackSpeed would return secret.
---In 12.0+ each line is auto-surfaced, so `leftText` / `rightText` /
---`leftColor` etc. are direct fields on the line table — no
---`TooltipUtil.SurfaceArgs` step (and that helper is no longer present in
---this client). We scan every line in tooltip order and accept the first
---decimal in [0.5, 4.0] from `rightText` — speed is always rendered on
---the right side of the damage/speed line, and we don't key on the word
---"Speed" so the scan is localization-independent. The preamble lines
---(item name, item level, slot/type) carry no decimals in that range, so
---the first hit is the damage/speed line even when extra preamble
---(Heroic / Modified / catalyst tags) pushes it past index 6. The decimal
---separator is locale-dependent ("Speed 3.60" on enUS / zh*, "Speed 3,60"
---on most European locales) — `[%.,]` matches either, and we splice the
---captures back together with a period before `tonumber`, since `tonumber`
---itself only accepts period-decimals.
---A failed read (tooltip not yet populated, sparse data, etc.) leaves the
---prior cached value intact.
swingState.refreshMainhandSpeed = function()
    local td = C_TooltipInfo.GetInventoryItem("player", INVSLOT_MAINHAND)
    if not (td and td.lines) then return end
    for i = 1, #td.lines do
        local line = td.lines[i]
        local s = line and line.rightText
        if s then
            local intPart, fracPart = s:match("(%d+)[%.,](%d+)")
            if intPart and fracPart then
                local n = tonumber(intPart .. "." .. fracPart)
                if n and n >= 0.5 and n <= 4.0 then
                    private.cachedMainhandSpeed = n
                    return
                end
            end
        end
    end
end

---Updates which resource segment shows the swing timer fill.
---Colors the filling segment lighter; restores normal color on all others.
---Hides swing fill when HP is at max or timer is inactive.
swingState.updateBars = function()
    if not swingState.startTime or not private.cachedMainhandSpeed or not private.swingHasteMult then return end

    local currentHP = UnitPower("player", Enum.PowerType.HolyPower)
    local maxHP = UnitPowerMax("player", Enum.PowerType.HolyPower)

    -- Restore normal color on the old swing segment
    if swingState.fillIndex and swingState.fillIndex <= activeResourceCount then
        local oldFrame = resourceFrames[swingState.fillIndex]
        local r, g, b, a = getResourceColor()
        oldFrame.bar:SetStatusBarColor(r, g, b, a)
        -- If this segment is depleted, zero out the fill we were animating
        if swingState.fillIndex > currentHP then
            oldFrame.bar:SetValue(0)
        end
    end

    -- Determine the next segment to fill
    local nextIndex = currentHP + 1
    if currentHP >= maxHP or nextIndex > activeResourceCount then
        -- HP is full — show overflow border if enabled, otherwise stop
        swingState.fillIndex = nil
        if currentHP >= maxHP and getSettings().paladin_swing_overflow and activeResourceCount > 0 and resourceFrames[activeResourceCount] then
            local maxFrame = resourceFrames[activeResourceCount]
            local border = getOrCreateOverflowBorder(maxFrame)
            local swR, swG, swB = getSwingTimerColor()
            border:SetBackdropBorderColor(swR, swG, swB, 0)
            border:Show()
            swingState.overflowGlowing = false

            if swingState.eventFrame then
                -- Store color on the frame so the pre-defined OnUpdate can read it.
                swingState.eventFrame._swR = swR
                swingState.eventFrame._swG = swG
                swingState.eventFrame._swB = swB
                swingState.eventFrame:SetScript("OnUpdate", swingState.eventFrame._overflowOnUpdate)
            end
        else
            hideOverflowBorder()
            if swingState.eventFrame then
                swingState.eventFrame:SetScript("OnUpdate", nil)
            end
        end
        return
    end

    -- Normal mode: fill the next depleted pip
    hideOverflowBorder()
    swingState.fillIndex = nextIndex
    local swR, swG, swB, swA = getSwingTimerColor()
    resourceFrames[nextIndex].bar:SetStatusBarColor(swR, swG, swB, swA)

    -- Start or replace OnUpdate for normal pip fill
    if swingState.eventFrame then
        swingState.eventFrame:SetScript("OnUpdate", swingState.eventFrame._pipFillOnUpdate)
    end
end

---Creates and registers the swing-detection event frame. Each successful
---Crusading Strikes swing anchors `swingState.startTime`; the period itself is
---deterministic — `cachedMainhandSpeed × CRUSADING_STRIKES_PERIOD_FACTOR /
---swingHasteMult` — so a delayed swing (out-of-range, parry/dodge, lag) cannot
---poison the baseline. The cache is primed from a tooltip scan
---(`C_TooltipInfo.GetInventoryItem`, non-secret) at register time and
---refreshed on PLAYER_EQUIPMENT_CHANGED (mainhand only) and
---PLAYER_ENTERING_WORLD (covers reload-mid-combat / mid-M+ where tooltip
---data may not be ready at register time). OnUpdate handlers consume
---`private.swingHasteDirty` lazily so
---aura/cooldown fires collapse into one sample per frame.
swingState.registerEvents = function()
    if not swingState.eventFrame then
        swingState.eventFrame = CreateFrame("Frame")
        swingState.eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
            if event == "PLAYER_EQUIPMENT_CHANGED" then
                -- `unit` carries the equipment slot for this event signature.
                if unit == INVSLOT_MAINHAND then
                    swingState.refreshMainhandSpeed()
                end
                return
            end
            if event == "PLAYER_ENTERING_WORLD" then
                swingState.refreshMainhandSpeed()
                return
            end
            if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
                -- Haste-shift events (UNIT_AURA, SPELL_UPDATE_COOLDOWN): debounce
                -- via the dirty flag; next OnUpdate tick resamples once.
                private.swingHasteDirty = true
                return
            end
            if unit ~= "player" then return end
            if spellID ~= SRC.CRUSADING_STRIKES_SPELL then return end

            -- Reject SUCCEEDED events that arrive too soon after the last accepted
            -- swing. Cleaving auto-attacks (Blessed Champion, 403010) and
            -- Windfury-style extra swings fire UNIT_SPELLCAST_SUCCEEDED in rapid
            -- bursts for 408385; without this guard the within-burst events
            -- would re-anchor swingState.startTime mid-cycle and pin the pip-fill bar
            -- at fraction≈1. 0.5s is well below the minimum realistic weapon
            -- swing cycle and well above any legitimate paired-event spacing.
            local now = GetTime()
            if swingState.startTime and (now - swingState.startTime) < 0.5 then return end

            -- Sample haste from Redemption's cast time (non-secret). UnitAttackSpeed
            -- is a secret value in 12.0+; Redemption's fixed 10s base scales linearly
            -- with haste, so hasteMult = 10000 / castTime.
            local info = C_Spell.GetSpellInfo(7328)
            if info and info.castTime and info.castTime > 0 then
                private.swingHasteMult = 10000 / info.castTime
                private.swingHasteDirty = false
            end
            -- Zone-in can unregister → re-register after PLAYER_ENTERING_WORLD with the
            -- tooltip not yet populated, leaving no speed and no later event to retry.
            if not private.cachedMainhandSpeed then
                swingState.refreshMainhandSpeed()
            end
            swingState.startTime = now
            swingState.updateBars()
        end)

        -- Pre-defined OnUpdate handlers stored on the frame to avoid creating
        -- a new closure on every UNIT_POWER_FREQUENT event.
        swingState.eventFrame._overflowOnUpdate = function()
            if private.swingHasteDirty then
                swingState.refreshHasteMult()
                private.swingHasteDirty = false
            end
            if not swingState.startTime or not private.cachedMainhandSpeed or not private.swingHasteMult then return end
            local swingDuration = private.cachedMainhandSpeed * SRC.CRUSADING_STRIKES_PERIOD_FACTOR / (private.swingHasteMult * private.swingZealotsFervorMult)
            if swingDuration <= 0 then return end
            local hp = UnitPower("player", Enum.PowerType.HolyPower)
            local mx = UnitPowerMax("player", Enum.PowerType.HolyPower)
            if hp < mx then
                swingState.updateBars()
                return
            end
            local elapsed = GetTime() - swingState.startTime
            local fraction = math.min(1, elapsed / swingDuration)
            if fraction >= 1 then
                if not swingState.overflowGlowing then
                    swingState.overflowGlowing = true
                    swingState.overflowBorder:SetBackdropBorderColor(swingState.eventFrame._swR, swingState.eventFrame._swG, swingState.eventFrame._swB, 1)
                    if getSettings().paladin_swing_overflow_glow then
                        swingState.overflowBorder.pulseAnim:Play()
                    end
                end
            else
                swingState.overflowBorder:SetBackdropBorderColor(swingState.eventFrame._swR, swingState.eventFrame._swG, swingState.eventFrame._swB, fraction)
            end
        end

        swingState.eventFrame._pipFillOnUpdate = function()
            if private.swingHasteDirty then
                swingState.refreshHasteMult()
                private.swingHasteDirty = false
            end
            if not swingState.startTime or not private.cachedMainhandSpeed or not private.swingHasteMult then return end
            if not swingState.fillIndex or swingState.fillIndex > activeResourceCount then return end
            local swingDuration = private.cachedMainhandSpeed * SRC.CRUSADING_STRIKES_PERIOD_FACTOR / (private.swingHasteMult * private.swingZealotsFervorMult)
            if swingDuration <= 0 then return end
            local elapsed = GetTime() - swingState.startTime
            local fraction = math.min(1, elapsed / swingDuration)
            resourceFrames[swingState.fillIndex].bar:SetValue(fraction)
        end
    end
    swingState.eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Haste-shift events drive lazy resampling of Redemption's cast time via
    -- private.swingHasteDirty. UNIT_AURA catches aura-driven haste (Avenging
    -- Wrath, Crusade, Bloodlust, trinket procs); SPELL_UPDATE_COOLDOWN fires
    -- alongside most other haste transitions in combat.
    swingState.eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    swingState.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    -- Mainhand swap → re-read cached weapon speed on the same frame as the equip.
    swingState.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    -- Reload / login / zone-in retries: tooltip data may not be populated at
    -- the very first swingState.refreshMainhandSpeed() call below if item info hasn't
    -- streamed in yet. PLAYER_ENTERING_WORLD reliably fires after that.
    swingState.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Prime the cache so the predictor has a period as soon as the first swing
    -- event anchors swingState.startTime.
    swingState.refreshMainhandSpeed()
    -- Resolve Zealot's Fervor rank now; PLAYER_TALENT_UPDATE → Refresh re-runs
    -- registerEvents() on respec, so the configID-keyed cache invalidates here.
    swingState.refreshZealotsFervorMult()
    private.swingHasteDirty = true
    swingState.updateBars()
end

---Unregisters swing timer events and resets all state.
swingState.unregisterEvents = function()
    if swingState.eventFrame then
        swingState.eventFrame:UnregisterAllEvents()
        swingState.eventFrame:SetScript("OnUpdate", nil)
    end
    -- Restore normal color on the swing segment
    if swingState.fillIndex and swingState.fillIndex <= #resourceFrames then
        local r, g, b, a = getCustomResourceColor()
        if not r then
            r, g, b, a = getResourceColor()
        end
        resourceFrames[swingState.fillIndex].bar:SetStatusBarColor(r, g, b, a)
    end
    hideOverflowBorder()
    swingState.startTime = nil
    private.cachedMainhandSpeed = nil
    private.swingHasteMult = nil
    private.swingHasteDirty = true
    swingState.fillIndex = nil
end

-- ── Skyriding Vigor update functions ──────────────────────────────────────────

---Re-reads the Thrill of the Skies aura on player, updates vigorState.isThrill,
---and applies the corresponding color to every Vigor bar. Called from the
---UNIT_AURA handler and during Vigor setup. Safe to call outside Vigor mode.
local refreshVigorThrillState = function()
    if activeResourceCount == 0 or playerPowerType ~= SRC.SKYRIDING_VIGOR then return end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(SRC.THRILL_OF_THE_SKIES_SPELL_ID)
    vigorState.isThrill = aura ~= nil
    local settings = getSettings()
    local c = vigorState.isThrill and settings.vigor_thrill_color or settings.vigor_color
    local r, g, b = c[1], c[2], c[3]
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetStatusBarColor(r, g, b, 1)
        resourceFrames[i].bg:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, 0.8)
    end
end

---Reads C_Spell.GetSpellCharges for vigor. Updates vigorState.startTime/vigorState.fillDuration
---for the recharging charge and sets all bar fills immediately.
---Returns true if vigor is not at maximum (caller should keep OnUpdate active).
local refreshVigorValues = function()
    local chargeInfo = C_Spell.GetSpellCharges(SRC.VIGOR_SPELL_ID)
    if not chargeInfo then return false end

    local current = chargeInfo.currentCharges
    local max = chargeInfo.maxCharges
    local prevCharges = vigorState.charges
    vigorState.charges = current

    for i = 1, activeResourceCount do
        if i <= current then
            resourceFrames[i].bar:SetValue(1)
        elseif i > current + 1 then
            resourceFrames[i].bar:SetValue(0)
        end
    end

    if current >= max then
        vigorState.startTime = nil
        vigorState.fillDuration = nil
        return false
    end

    vigorState.fillDuration = chargeInfo.cooldownDuration
    if vigorState.fillDuration <= 0 then
        vigorState.fillDuration = 10 -- safe fallback
    end

    if vigorState.startTime == nil or current > prevCharges then
        -- Initial sync or charge gained: start from cooldown progress
        vigorState.startTime = chargeInfo.cooldownStartTime
        if current + 1 <= activeResourceCount then
            local elapsed = GetTime() - vigorState.startTime
            local fraction = math.min(1, elapsed / vigorState.fillDuration)
            resourceFrames[current + 1].bar:SetValue(fraction)
        end
    elseif current < prevCharges then
        -- Charge spent: partial fill carries over, keep vigorState.startTime unchanged
        if vigorState.startTime and vigorState.fillDuration and current + 1 <= activeResourceCount then
            local fraction = math.min(1, (GetTime() - vigorState.startTime) / vigorState.fillDuration)
            resourceFrames[current + 1].bar:SetValue(fraction)
        end
    end

    return true
end

---OnUpdate callback for Vigor bars. Computes fill fraction from
---vigorState.startTime/vigorState.fillDuration and GetTime().
local onUpdateVigor = function()
    local fraction = 0
    if vigorState.startTime and vigorState.fillDuration then
        fraction = math.min(1, (GetTime() - vigorState.startTime) / vigorState.fillDuration)
    end

    local inProgress = vigorState.charges + 1
    for i = 1, activeResourceCount do
        if i <= vigorState.charges then
            resourceFrames[i].bar:SetValue(1)
        elseif i == inProgress then
            resourceFrames[i].bar:SetValue(fraction)
        else
            resourceFrames[i].bar:SetValue(0)
        end
    end
    -- Update speed text directly in OnUpdate when enabled
    if rowFrame and rowFrame.valueText then
        local settings = getSettings()
        if settings.skyriding_show_speed then
            local _, _, forwardSpeed = private.compat.GetGlidingInfo()
            if forwardSpeed and forwardSpeed > 0 then
                rowFrame.valueText:SetText(string.format("%d", forwardSpeed * 14.285))
                rowFrame.valueText:Show()
            else
                rowFrame.valueText:Hide()
            end
        end
    end
end

-- ── Discipline Priest Radiance charge update functions ─────────────────────

---Updates the Radiance charge bar display. Same secret-safe pattern as
---updateAimedShotCharges: per-segment bars use offset MinMax (i-1, i) so the
---potentially-secret currentCharges auto-clamps each segment full/empty via
---SetValue (AllowedWhenTainted). The reference bar (radRefBar) drives the
---recharge overlay (radRechargeBar) anchor edge, and SetTimerDuration fed by
---C_Spell.GetSpellChargeDuration (returns a NeverSecret DurationObject)
---animates the in-progress segment via the engine — no addon-side OnUpdate
---and no arithmetic on currentCharges / cooldownStartTime / cooldownDuration.
local updateRadianceCharges = function()
    if activeResourceCount == 0 then return end
    local chargeInfo = C_Spell.GetSpellCharges(SRC.RADIANCE_SPELL_ID)
    if chargeInfo then
        cachedRadianceCharges = chargeInfo.currentCharges
    end
    for i = 1, activeResourceCount do
        resourceFrames[i].bar:SetMinMaxValues(i - 1, i)
        resourceFrames[i].bar:SetValue(cachedRadianceCharges, barInterpolation)
    end

    if radRefBar then
        radRefBar:SetValue(cachedRadianceCharges, barInterpolation)
    end

    local duration = C_Spell.GetSpellChargeDuration(SRC.RADIANCE_SPELL_ID)
    if duration and radRechargeBar then
        radRechargeBar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
        radRechargeBar:Show()
    elseif radRechargeBar then
        radRechargeBar:Hide()
    end

    -- Tier B threshold fold — re-evaluate on each charge change.
    local tr, tg, tb, ta = getCustomResourceColor()
    if tr then
        applyThresholdColorsSecret(cachedRadianceCharges, CreateColor(tr, tg, tb, ta or 1))
    end

    updateValueText()
end

-- ────────────────────────────────────────────────────────────────────────────

---Value-text derivation for every resource that is a PURE read of file-scope
---state, keyed by the same token the rest of the file dispatches on. The
---`elseif` chain this replaced put the `else` fallthrough — the common case for
---most specs, plain `UnitPower` — behind seventeen comparisons on a
---per-power-event path; a keyed lookup answers in one.
---
---> ⚠️ **This table must stay directly above `updateValueText`, below every
---> local it reads.** Each row is a closure and Lua 5.1 captures at definition
---> time, so a row moved above (say) `cachedStaggerPct` would capture nil, read
---> as a global forever, and print `0%` with no error anywhere — the silent
---> captured-nil VALUE case in `.context/patterns.md`. The bytecode scan is what
---> catches it: a mis-placed row shows up as a new `GETGLOBAL`.
---
---Four cases deliberately stay as branches below rather than becoming rows,
---because a row cannot express what they do. `SoulShards` reads the per-call
---`settings`. `IGNORE_PAIN_PROT` and the stack strips write no value at all —
---they leave the bound FontString's text alone, which is neither writing nor
---hiding. `SKYRIDING_VIGOR` needs `settings` too and HIDES in speed mode.
---Widening the row contract to cover those (a second return, or passing
---`valueText` in) would cost more than the branches it removed.
---@type table<any, fun(): string|number>
local VALUE_TEXT = {
    [Enum.PowerType.Essence] = function() return cachedCurrentEssence end,
    [SRC.SOUL_FRAG_VENGEANCE] = function() return cachedVengeanceFragments end,
    -- Forecast text (if enabled) is handled by the dedicated pre-gate block in
    -- updateValueText. This is the plain value path for when forecast text is off.
    [SRC.SOUL_FRAG_DEVOURER] = function() return cachedDevourerSouls end,
    [SRC.WW_CHARGES_FURY] = function() return wwState.charges end,
    [SRC.TOTS_CHARGES_SURVIVAL] = function() return totsState.charges end,
    [SRC.ICICLES_FROST] = function() return iciclesState.count end,
    [SRC.IRONFUR_GUARDIAN] = function() return #ironfurState.instances end,
    [SRC.MW_CHARGES_ENHANCEMENT] = function() return mwState.charges end,
    [SRC.FIRE_BLAST_CHARGES] = function() return cachedFireBlastCharges end,
    [SRC.AIMED_SHOT_CHARGES] = function() return cachedAimedShotCharges end,
    [SRC.RADIANCE_CHARGES] = function() return cachedRadianceCharges end,
    [SRC.STAGGER_BREWMASTER] = function()
        return math.floor(cachedStaggerPct + 0.5) .. "%"
    end,
    [SRC.VITALITY_MONK] = function()
        return AbbreviateLargeNumbers(getVitalityAmount())
    end,
    [Enum.PowerType.Runes] = function()
        local ready = 0
        for i = 1, activeResourceCount do
            if runeState.startTimes[i] == nil then
                ready = ready + 1
            end
        end
        return ready
    end,
}

---Updates the centered resource value text. Shows the current integer resource count
---when show_value is enabled; hides the text otherwise.
---Most resources derive their value from `VALUE_TEXT`; the four that cannot are
---the branches below. Static: UnitPower.
updateValueText = function()
    local valueText = rowFrame and rowFrame.valueText
    if not resourcesFrame or not valueText then return end

    local settings = getSettings()

    -- Devourer Reap forecast text: gated by its own show-text toggle, independent
    -- of the global show_value. `cachedDevourerSouls` (from
    -- C_Spell.GetSpellCastCount) can be a SECRET number in combat, so the format
    -- is additive — no arithmetic on any value, all numbers piped straight
    -- through SetFormattedText's %d slot (AllowedWhenTainted).
    local devourerText = playerPowerType == SRC.SOUL_FRAG_DEVOURER
        and settings.devourer_reap_forecast
        and settings.devourer_reap_forecast_show_text
        and activeResourceCount > 0
    -- Show/Hide on the bound tap FS is legal only while auras are non-secret;
    -- a mid-combat toggle-off therefore leaves the count visible until the
    -- first non-secret tick converges it.
    --
    -- ROW 1 ONLY, for the reason `refreshResourceCount`'s hideAll guard gives:
    -- `reapFc` is singleton state and this runs once per row. `devourerText` is
    -- false on every row that is not the Devourer bar, so an unguarded pass
    -- would hide the count and — worse — call applyTapAnchors(false), clearing
    -- the `seamApplied` flag row 1 had just set and flip-flopping the seam every
    -- pass. Devourer is always row 1 (primary-only resource), so row 1 owns
    -- every reapFc write and rows >= 2 skip rather than flat-write a default.
    -- A non-Devourer character's row 1 still evaluates `devourerText` false and
    -- so still runs the genuine teardown.
    if rowIndex == 1 then
        if reapFc.tapStacks and not auraTap.blocked() then
            reapFc.tapStacks:SetShown(devourerText or false)
        end
        reapFc.applyTapAnchors(devourerText or false)
    end
    if devourerText then
        -- Display-only composition — Blizzard writes the secret SF count into
        -- our own bound FontString (reapFc.tapStacks) and the engine renders
        -- it; we only ever write our own soul-count text.  Read-back is dead —
        -- see patterns-secrets.md "Aura-tap".
        reapFc.ensureTapStacks()
        if reapFc.tapFontDirty and reapFc.tapStacks
            and not auraTap.blocked() then
            -- Deferred font re-apply: the fonts pass ran while the bound
            -- FS was write-blocked (auras secret); converge now.
            reapFc.tapFontDirty = false
            reapFc.applyTapFont()
        end
        valueText:SetFormattedText("%d", cachedDevourerSouls)
        valueText:Show()
        return
    end

    if not settings.show_value or activeResourceCount == 0 then
        valueText:Hide()
        return
    end

    local value
    local derive = VALUE_TEXT[playerPowerType]
    if derive then
        value = derive()
    elseif playerPowerType == Enum.PowerType.SoulShards then
        local shardPower = UnitPower("player", playerPowerType, true)
        local shardModifier = UnitPowerDisplayMod(Enum.PowerType.SoulShards)
        if isDestructionWarlock and settings.warlock_shard_fragments then
            value = (shardModifier ~= 0) and string.format("%.1f", shardPower / shardModifier) or "0.0"
        else
            value = (shardModifier ~= 0) and math.floor(shardPower / shardModifier) or 0
        end
    elseif playerPowerType == SRC.IGNORE_PAIN_PROT then
        -- Both modes render the text from the aura tap's bound FontString.
        return
    elseif STACK_STRIPS[playerPowerType] then
        -- Nothing legal to write for any stack strip: the count is secret. The
        -- ones that show a number take it from the stack tap's bound
        -- FontString, which updateStackPips hides this one behind; the ones
        -- that do not (target-bound, or STACK_STRIPS `noReadout`) show none.
        return
    elseif playerPowerType == SRC.SKYRIDING_VIGOR then
        if getSettings().skyriding_show_speed then
            -- Speed display is handled by OnUpdate; hide here to avoid flicker
            valueText:Hide()
            return
        end
        value = vigorState.charges
    else
        value = SRC.staticPower(playerPowerType)
    end

    valueText:SetText(value)
    valueText:Show()
end

---Queries UnitPowerMax for the current talent configuration and updates the visible resource
---frames accordingly. Creates new pool entries when more frames are needed; hides trailing
---frames when fewer are needed. Updates activeResourceCount and re-runs layoutBars.
local refreshResourceCount = function()
    if not resourcesFrame then return end

    -- Reset MinMaxValues on all existing bars to default (0, 1).
    -- Fire Blast uses offset ranges (i-1, i) which would break other power types.
    for _, rf in ipairs(resourceFrames) do
        rf.bar:SetMinMaxValues(0, 1)
    end

    -- Hide any Devourer Reap forecast overlays from a previous spec — the
    -- SOUL_FRAG_DEVOURER branch below re-shows them via reapFc.update() when
    -- needed. Without this, switching off Devourer leaves the slab/ammo/pip
    -- visible on top of the Vengeance fragments or whatever bar reuses
    -- resourceFrames[1] next.
    --
    -- ROW 1 ONLY. `reapFc` is singleton state and this function runs once per
    -- row, so an unguarded hide is the hide-then-correct defect
    -- `.context/patterns.md` catalogues: row 1 hides and re-shows via the
    -- Devourer branch below, then row 2 hides again and never re-shows —
    -- overlays gone until the next soul-power event, i.e. a flicker in combat
    -- and stale-hidden out of it. Row 1 is the only row that can ever own them:
    -- SOUL_FRAG_DEVOURER appears solely in `SRC.specSecondaryPower`, so it is
    -- always the PRIMARY, and extras append after the primary. A non-Devourer
    -- character still gets the genuine teardown, because its row 1 runs this.
    if rowIndex == 1 then
        reapFc.hideAll()
    end

    -- Hide breakpoint pips from a previous continuous-power spec — the
    -- continuous branch below re-applies them.
    -- Row-guarded for the same reason reapFc.hideAll() above is:
    -- `continuousPipHost` is a singleton whose `bar` is only ever written by the
    -- continuous branch below, from `resourceFrames[1]`. The guard is
    -- behaviour-neutral today — no continuous-power spec (Elemental / Balance /
    -- Shadow) has an extra row, so a row-2 Clear would already hit an empty host
    -- — and it removes the trap rather than leaving a comment as its only
    -- defence, which is what a future continuous-power extra row would need.
    if rowIndex == 1 then
        private.BreakpointPips.Clear(continuousPipHost)
    end

    -- ── Fury Warrior Whirlwind charges: fixed 4 discrete segments ──────────────
    if playerPowerType == SRC.WW_CHARGES_FURY then
        local n = SRC.WW_MAX_CHARGES
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Survival Hunter Tip of the Spear: fixed 3 discrete segments ────────────
    if playerPowerType == SRC.TOTS_CHARGES_SURVIVAL then
        local n = SRC.TOTS_MAX_CHARGES
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Frost Mage Icicles: fixed 5 discrete segments ───────────────────────────
    if playerPowerType == SRC.ICICLES_FROST then
        local n = SRC.ICICLES_MAX
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Guardian Druid Ironfur: single bar with tick marks ──────────────────────
    if playerPowerType == SRC.IRONFUR_GUARDIAN then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        layoutBars()
        return
    end

    -- ── Enhancement Shaman Maelstrom Weapon: one segment per stack ────────────
    if playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        local n = mwState.variant.max
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Fire Mage Fire Blast charges: discrete segments from talent check ──
    if playerPowerType == SRC.FIRE_BLAST_CHARGES then
        local max = getFireBlastMaxCharges()
        cachedFireBlastMax = max
        while #resourceFrames < max do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= max then rf:Show() else rf:Hide() end
        end
        activeResourceCount = max
        if activeResourceCount > 0 then
            layoutBars()
            setupFireBlastRechargeBar()
        end
        return
    end

    -- ── Marksmanship Hunter Aimed Shot charges: discrete segments ─────────────
    if playerPowerType == SRC.AIMED_SHOT_CHARGES then
        local chargeInfo = C_Spell.GetSpellCharges(SRC.AIMED_SHOT_SPELL_ID)
        local max = chargeInfo and chargeInfo.maxCharges or 2
        cachedAimedShotMax = max
        while #resourceFrames < max do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= max then rf:Show() else rf:Hide() end
        end
        activeResourceCount = max
        if activeResourceCount > 0 then
            layoutBars()
            setupAimedShotRechargeBar()
        end
        return
    end

    -- ── Discipline Priest Radiance charges: discrete segments with recharge overlay ──
    if playerPowerType == SRC.RADIANCE_CHARGES then
        local chargeInfo = C_Spell.GetSpellCharges(SRC.RADIANCE_SPELL_ID)
        local max = chargeInfo and chargeInfo.maxCharges or SRC.RADIANCE_DEFAULT_MAX
        cachedRadianceMax = max
        while #resourceFrames < max do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= max then rf:Show() else rf:Hide() end
        end
        activeResourceCount = max
        if activeResourceCount > 0 then
            layoutBars()
            setupRadianceRechargeBar()
        end
        return
    end

    -- Hide Fire Blast / Aimed Shot / Radiance recharge systems when switching away
    if fbClipFrame then fbClipFrame:Hide() end
    if asClipFrame then asClipFrame:Hide() end
    if radClipFrame then radClipFrame:Hide() end

    -- ── Vengeance Soul Fragments: fixed discrete segments ─────────────────────
    if playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        local n = SRC.VENG_SOUL_FRAG_MAX
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Devourer Soul Fragments: single fill bar (+ optional Reap forecast overlays) ──
    if playerPowerType == SRC.SOUL_FRAG_DEVOURER then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        cachedDevourerMax = getDevourerSoulMax()
        resourceFrames[1].bar:SetMinMaxValues(0, cachedDevourerMax)
        layoutBars()
        reapFc.update()
        return
    end

    -- ── Continuous power bars (Elemental Maelstrom, Balance Astral Power, Shadow Insanity) ──
    if SRC.continuousBarPowers[playerPowerType] then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        resourceFrames[1].bar:SetMinMaxValues(0, UnitPowerMax("player", playerPowerType))
        layoutBars()
        -- Breakpoint pips: re-apply after layout so positions use the final
        -- bar size (and, in absolute mode, the current UnitPowerMax — the
        -- UNIT_MAXPOWER handler routes back through here).
        continuousPipHost.bar = resourceFrames[1].bar
        continuousPipHost.key = private.BreakpointPips.GetKeyForCurrentSpec("secondary")
        local pipR, pipG, pipB, pipA = getCustomResourceColor()
        if pipR == nil then
            pipR, pipG, pipB, pipA = getResourceColor()
        end
        continuousPipBaseColor[1], continuousPipBaseColor[2], continuousPipBaseColor[3], continuousPipBaseColor[4] = pipR, pipG, pipB, pipA or 1
        private.BreakpointPips.Apply(continuousPipHost)
        return
    end

    -- ── Brewmaster Stagger: single fill bar ─────────────────────────────────
    if playerPowerType == SRC.STAGGER_BREWMASTER then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        resourceFrames[1].bar:SetMinMaxValues(0, 100)
        layoutBars()
        layoutStaggerPips()
        return
    end

    -- ── Monk Vitality: single fill bar ──────────────────────────────────────
    if playerPowerType == SRC.VITALITY_MONK then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        resourceFrames[1].bar:SetMinMaxValues(0, UnitHealthMax("player"))
        layoutBars()
        return
    end

    -- ── Protection Warrior Ignore Pain: single bar ─────────────────────────
    if playerPowerType == SRC.IGNORE_PAIN_PROT then
        while #resourceFrames < 1 do createResourceFrame() end
        resourceFrames[1]:Show()
        for i = 2, #resourceFrames do resourceFrames[i]:Hide() end
        activeResourceCount = 1
        -- The fill is the aura tap's bar now (ipState.ensureTap), overlaid on
        -- this one; the host stays empty so nothing stale shows through when
        -- the aura drops and the engine hides the tap.
        resourceFrames[1].bar:SetValue(0)
        layoutBars()
        -- No pandemic overlay is built here any more: the glow is a native
        -- pandemic region on the aura-tap button, so it must be a DESCENDANT of
        -- that button (ValidateInboundScriptObject) and is created inside
        -- ipState.ensureTap's initializeFrame instead.
        return
    end

    -- ── Stack strips: discrete stack segments ─────────────────────────────
    -- Hosts only; the fill belongs to the pip tap, so these stay empty and
    -- nothing stale shows through when the aura drops (or, for Shatter, when
    -- the target changes) and the engine hides the taps.
    --
    -- The cap is re-resolved here on every pass rather than cached, so it
    -- agrees with `stackPipSpec`'s -- talent- and spec-scaled caps move with no
    -- event of their own, and hosts built to a different length than the tap is
    -- exactly the failure this shares one source with.
    local strip = STACK_STRIPS[playerPowerType]
    if strip then
        local n = stackTap.segmentsFor(strip.cap())
        while #resourceFrames < n do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= n then rf:Show() else rf:Hide() end
        end
        activeResourceCount = n
        emptyStackHosts(n)
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    -- ── Skyriding Vigor: discrete bars with partial fill ──────────────────
    if playerPowerType == SRC.SKYRIDING_VIGOR then
        local chargeInfo = C_Spell.GetSpellCharges(SRC.VIGOR_SPELL_ID)
        local max = chargeInfo and chargeInfo.maxCharges or 6
        while #resourceFrames < max do createResourceFrame() end
        for i, rf in ipairs(resourceFrames) do
            if i <= max then rf:Show() else rf:Hide() end
        end
        activeResourceCount = max
        if activeResourceCount > 0 then layoutBars() end
        return
    end

    local n = UnitPowerMax("player", playerPowerType)

    -- Grow the pool if the new maximum exceeds what we have created so far
    while #resourceFrames < n do
        createResourceFrame()
    end

    -- Show the first n frames; hide any extras beyond the new maximum
    for i, resourceFrame in ipairs(resourceFrames) do
        if i <= n then
            resourceFrame:Show()
        else
            resourceFrame:Hide()
        end
    end

    activeResourceCount = n

    if activeResourceCount > 0 then
        layoutBars()
    end
end

---Event name and power token the per-row power dispatch is currently running
---for. Module-level rather than upvalues of a per-event closure: `withRow` takes
---a callback, and building one would allocate on every UNIT_POWER_FREQUENT tick.
---@type string?
local dispatchEvent
---@type string?
local dispatchToken

---One active row's share of a power event. Runs under `withRow`, so every
---`playerPowerType` / `resourceFrames` / `activeResourceCount` read below is that
---row's own: the branch chain self-selects, and a row that does not own the
---event falls through without doing anything.
local dispatchPowerEvent = function()
    local event, arg2 = dispatchEvent, dispatchToken

    -- ── Runes ─────────────────────────────────────────────────────────────────
    -- Self-selects on the row's own power type like every branch below it:
    -- runeState.refreshValues writes straight into resourceFrames without
    -- checking, so a non-rune row offered this event would drive rune fills into
    -- its own segments.
    if playerPowerType == Enum.PowerType.Runes and event == "RUNE_POWER_UPDATE" then
        if not resourcesFrame then return end
        if runeState.refreshValues() then
            resourcesFrame:SetScript("OnUpdate", runeState.onUpdate)
        else
            resourcesFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    -- ── Fire Mage Fire Blast charges ──────────────────────────────────────────
    if playerPowerType == SRC.FIRE_BLAST_CHARGES then
        if not resourcesFrame then return end
        if event == "SPELL_UPDATE_CHARGES" then
            updateFireBlastCharges()
        end
        return
    end

    -- ── Marksmanship Hunter Aimed Shot charges ───────────────────────────────
    if playerPowerType == SRC.AIMED_SHOT_CHARGES then
        if not resourcesFrame then return end
        if event == "SPELL_UPDATE_CHARGES" then
            updateAimedShotCharges()
        end
        return
    end

    -- ── Discipline Priest Radiance charges ──────────────────────────────────
    if playerPowerType == SRC.RADIANCE_CHARGES then
        if not resourcesFrame then return end
        if event == "SPELL_UPDATE_CHARGES" then
            updateRadianceCharges()
        end
        return
    end

    -- ── Vengeance Soul Fragments ──────────────────────────────────────────────
    if playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        if not resourcesFrame then return end
        if event == "SPELL_UPDATE_USES" then
            updateVengeanceSoulFragments()
        end
        return
    end

    -- ── Devourer Soul Fragments ───────────────────────────────────────────────
    if playerPowerType == SRC.SOUL_FRAG_DEVOURER then
        if not resourcesFrame then return end
        if event == "SPELL_UPDATE_USES" then
            updateDevourerSoulFragments()
        elseif event == "UNIT_AURA" or event == "SPELLS_CHANGED" then
            refreshDevourerMax()
            updateDevourerSoulFragments()
        end
        return
    end

    -- ── Brewmaster Stagger ────────────────────────────────────────────────────
    if playerPowerType == SRC.STAGGER_BREWMASTER then
        if not resourcesFrame then return end
        if event == "UNIT_AURA" or event == "UNIT_MAXHEALTH" then
            updateStaggerBar()
        end
        return
    end

    -- ── Monk Vitality ────────────────────────────────────────────────────────
    if playerPowerType == SRC.VITALITY_MONK then
        if not resourcesFrame then return end
        if event == "UNIT_MAXHEALTH" then
            refreshVitalityMax()
            updateVitalityBar()
        end
        return
    end

    -- ── Skyriding Vigor ─────────────────────────────────────────────────────
    if playerPowerType == SRC.SKYRIDING_VIGOR then
        if not resourcesFrame then return end
        if event == "ACTIONBAR_UPDATE_COOLDOWN" then
            refreshVigorValues()
            resourcesFrame:SetScript("OnUpdate", onUpdateVigor)
        elseif event == "UNIT_AURA" then
            refreshVigorThrillState()
        end
        return
    end

    -- ── Essence: haste-dirty signals (no power token; handle before the guard) ──
    -- Just flag dirty; the per-frame consumer collapses the burst into one sample.
    if playerPowerType == Enum.PowerType.Essence
        and (event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED"
            or event == "SPELL_UPDATE_COOLDOWN"
            or event == "UNIT_AURA"
            or event == "TRAIT_CONFIG_UPDATED") then
        private.hasteDirty = true
        return
    end

    -- Handle UNIT_POWER_POINT_CHARGE before the arg2 token guard. The event is
    -- registered only for ComboPoints, so it cannot arrive for a non-matching
    -- power type; and its payload is not guaranteed to carry the same token
    -- shape ("COMBO_POINTS") that UNIT_POWER_FREQUENT/UNIT_MAXPOWER use.
    if event == "UNIT_POWER_POINT_CHARGE" then
        updateComboPointColors()
        return
    end

    -- SRC.comboPointsOnTarget only: combo points sit on the target, so a new
    -- target is a new value. No payload, hence before the guard.
    if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
        if playerPowerType == Enum.PowerType.ComboPoints then
            updateResourceValues()
        end
        return
    end

    -- All remaining events carry a powerTypeToken (arg2) identifying which power
    -- type changed. Drop any event whose token does not match the player's
    -- secondary resource (e.g. Mana events on Evokers, Energy events on Rogues).
    local powerTypeToken = arg2
    if powerTypeToken == nil or powerTypeToken ~= SRC.powerTypeTokens[playerPowerType] then
        return
    end

    -- ── Continuous power bars: single fill, live value + max ────────────────────
    if SRC.continuousBarPowers[playerPowerType] then
        if not resourcesFrame then return end
        if event == "UNIT_MAXPOWER" then
            refreshResourceCount()
        end
        updateContinuousBar()
        return
    end

    -- ── Essence ───────────────────────────────────────────────────────────────
    if playerPowerType == Enum.PowerType.Essence then
        if not resourcesFrame then return end
        if event == "UNIT_MAXPOWER" then
            refreshResourceCount()
        end
        if refreshEssenceValues() then
            resourcesFrame:SetScript("OnUpdate", onUpdateEssence)
        else
            resourcesFrame:SetScript("OnUpdate", nil)
        end
        return
    end

    -- ── Static resources (ComboPoints, SoulShards, HolyPower, Chi, ArcaneCharges) ──
    if not SRC.staticPowerTypes[playerPowerType] then return end

    if event == "UNIT_MAXPOWER" then
        refreshResourceCount()
    end
    updateResourceValues()
    if playerPowerType == Enum.PowerType.HolyPower then
        if swingState.startTime then
            swingState.updateBars()
        end
        applyDivinePurposeTint()
    end
    if playerPowerType == Enum.PowerType.ComboPoints then
        updateComboPointColors()
    end
end

---Event frame for power value and max updates. The registrations are the UNION
---over the active rows (`registerPowerEvents` runs once per row), so one frame
---delivers every row's events and each row is offered every event in turn.
local powerEventFrame = CreateFrame("Frame")
powerEventFrame:SetScript("OnEvent", function(_, event, _, arg2)
    if not getEnabled() then return end
    dispatchEvent, dispatchToken = event, arg2
    for i = 1, activeRowCount do
        withRow(i, dispatchPowerEvent)
    end
end)

---Desired state of the sub-registrations `registerPowerEvents` decides but does
---not apply, accumulated across every active row and consumed by
---`applyPowerEventRegistrations`. One table rather than five file locals: this
---file manages Lua 5.1's 200-local ceiling deliberately. The keys are seeded
---here and only ever reassigned, never nilled, so a Refresh pass rewrites the
---same hash slots and allocates nothing.
---@type table<string, boolean>
local powerEventWants = {
    static = false,
    swing = false,
    cdg = false,
    spendPred = false,
    buildPred = false,
}

---Registers power events appropriate for the player's secondary resource type.
---Runes use RUNE_POWER_UPDATE; Essence uses UNIT_POWER_FREQUENT + UNIT_MAXPOWER;
---static resources use UNIT_POWER_FREQUENT + UNIT_MAXPOWER (+ UNIT_POWER_POINT_CHARGE
---for combo-point classes).
---
---Runs once per active row under `withRow`, so `powerEventFrame` ends up holding
---the union over the rows. Re-registering an event on a frame that already has
---it is a no-op, so repeated passes cannot duplicate anything; leftovers from a
---resource that left the set are cleared the way they always were, by the
---`powerEventFrame:UnregisterAllEvents()` in every power-type transition handler
---before the Refresh that re-registers the new union.
---
---The event registrations here are purely additive, which is what makes the
---union sound — but only while no two rows register the SAME event by different
---means. `RegisterEvent` and `RegisterUnitEvent` are not commutative: the second
---call replaces the first's unit filtering rather than widening it, so a row
---asking for a bare `UNIT_AURA` after another row's `RegisterUnitEvent("UNIT_AURA",
---"player")` would silently drop that row's filter (and vice versa). No two
---branches below overlap that way today. A new resource that shares an event
---with an existing one must use the same registration form for it.
---
---The sub-registrations with an else-position unregister (the swing timer, the
---Coup de Grâce strip, and the two prediction frames) are NOT applied here —
---they are only decided into `powerEventWants`, because applying them per row
---would let a later row tear down what an earlier row just asked for. See
---`applyPowerEventRegistrations`.
---
---`powerEventFrame`'s handler offers every event to every row in turn, so it
---reaches the right one whatever the row count. The DEDICATED frames the
---branches below delegate to (Whirlwind, Tip of the Spear, Icicles, Ironfur,
---Maelstrom Weapon, Vitality, the swing timer and the two prediction frames)
---write through the module-level pointers instead, which means row 1. That is
---the owning row for every resource they serve today — each is a whole-spec
---secondary, so it can only ever be the primary. A later task that puts one of
---them in a non-primary row must run its handler body under `withRow` on the
---row whose `rows[i].powerType` matches.
local registerPowerEvents = function()
    if playerPowerType == SRC.WW_CHARGES_FURY then
        registerWWEvents()
        return
    end
    if playerPowerType == SRC.TOTS_CHARGES_SURVIVAL then
        registerTotsEvents()
        return
    end
    if playerPowerType == SRC.ICICLES_FROST then
        iciclesState.registerEvents()
        return
    end
    if playerPowerType == SRC.IRONFUR_GUARDIAN then
        ironfurState.registerEvents()
        return
    end
    if playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        registerMwEvents()
        return
    end
    if playerPowerType == SRC.VITALITY_MONK then
        registerVitalityEvents()
        powerEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        return
    end
    if playerPowerType == SRC.IGNORE_PAIN_PROT then
        -- Nothing to register: the bar, the value text and the pandemic cue are
        -- all engine-driven off the aura tap, and Refresh converges the build.
        -- Still an explicit branch so IP does not fall through to the generic
        -- UNIT_POWER registration below.
        return
    end
    if playerPowerType == SRC.SHATTER_FREEZING then
        -- The pips are engine-driven off the target-bound tap; the only thing
        -- needing an event is re-pointing that tap when the target changes.
        shatterState.registerEvents()
        return
    end
    if STACK_STRIPS[playerPowerType] then
        -- Nothing to register: the pips and the count text are engine-driven off
        -- the stack tap, and Refresh converges the build. Still an explicit
        -- branch so none falls through to the generic UNIT_POWER registration
        -- below.
        return
    end
    if playerPowerType == SRC.FIRE_BLAST_CHARGES then
        powerEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        return
    end
    if playerPowerType == SRC.AIMED_SHOT_CHARGES then
        powerEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        return
    end
    if playerPowerType == SRC.RADIANCE_CHARGES then
        powerEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        return
    end
    if playerPowerType == Enum.PowerType.Runes then
        powerEventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    elseif playerPowerType == Enum.PowerType.Essence then
        powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        -- Option 2A: sample Rebirth's cast time (spellID 361227) on the events
        -- where haste can start or change state to derive haste-adjusted
        -- essenceFillDuration. FAILED/INTERRUPTED cover empower-specific
        -- early-release cases. SPELL_UPDATE_COOLDOWN is kept because it fires
        -- alongside most haste-relevant transitions in combat.
        powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        powerEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        -- UNIT_AURA catches aura-driven haste changes (trinket procs, Bloodlust
        -- on/off) that don't involve a cast. Noisy in combat but debounced to
        -- one Rebirth sample per frame via private.hasteDirty.
        powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        -- TRAIT_CONFIG_UPDATED catches respec changes to Innate Magic
        -- (+5%/+10% Essence regen) so the multiplier re-resolves on next frame.
        powerEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    elseif playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        powerEventFrame:RegisterEvent("SPELL_UPDATE_USES")
    elseif playerPowerType == SRC.SOUL_FRAG_DEVOURER then
        powerEventFrame:RegisterEvent("SPELL_UPDATE_USES")
        powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        -- 12.1 aura-tap slot for the souls-nearby count (secret in combat).
        -- No-op in combat or before valueText exists; updateValueText retries
        -- lazily out of combat.
        reapFc.ensureTapStacks()
        -- SPELLS_CHANGED fires on spell-override changes, including Moment of
        -- Craving's Reap → Eradicate swap toggling on/off. UNIT_AURA on the
        -- MoC aura is unreliable (secret), so without this the Reap forecast
        -- slab stays at the 10-cap width until the next Eradicate cast.
        powerEventFrame:RegisterEvent("SPELLS_CHANGED")
    elseif playerPowerType == SRC.STAGGER_BREWMASTER then
        powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    elseif playerPowerType == SRC.SKYRIDING_VIGOR then
        powerEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        powerEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    elseif SRC.continuousBarPowers[playerPowerType] then
        powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    elseif SRC.staticPowerTypes[playerPowerType] then
        powerEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        powerEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        if playerPowerType == Enum.PowerType.ComboPoints then
            -- Not an event on MoP Classic, which has no charged combo points.
            if C_EventUtils.IsEventValid("UNIT_POWER_POINT_CHARGE") then
                powerEventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
            end
            if SRC.comboPointsOnTarget then
                powerEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
                -- Classic's combo frame also redraws on this one; Forever's does not.
                if C_EventUtils.IsEventValid("COMBO_TARGET_CHANGED") then
                    powerEventFrame:RegisterEvent("COMBO_TARGET_CHANGED")
                end
            end
        end
        -- Decisions only from here down; applyPowerEventRegistrations applies
        -- them once the whole row set has had its turn.
        powerEventWants.static = true
        if playerPowerType == Enum.PowerType.HolyPower
            and getSettings().paladin_swing_timer
            and IsPlayerSpell(SRC.CRUSADING_STRIKES_TALENT) then
            powerEventWants.swing = true
        end
        if isCdGEligible() then
            powerEventWants.cdg = true
        end
        if playerPowerType == Enum.PowerType.SoulShards
            and getSettings().warlock_spend_prediction then
            powerEventWants.spendPred = true
        end
        buildPred.populate()
        if getSettings().builder_prediction and next(buildPred.spells) then
            powerEventWants.buildPred = true
        end
    end
end

---Applies the sub-registrations `registerPowerEvents` only decided, once every
---active row has been offered its turn.
---
---These four are the one non-additive part of the power-event set: each has an
---else-position unregister, so applying them from inside a per-row pass let a
---later row whose resource misses the condition tear down what an earlier row
---had just asked for. Deciding is therefore separated from applying — a row
---records what it wants, a register wins over another row's non-register, and an
---unregister fires only when NO active row asked for it.
---
---Nothing is applied unless some active row took the static-resource branch,
---which is the only branch that decided any of this before the rework: a lone
---Essence or Rune row must still leave all four untouched, exactly as it did.
---
---The wants are cleared on the way out, so the next Refresh starts from a clean
---slate with no separate begin step to forget.
local applyPowerEventRegistrations = function()
    if powerEventWants.static then
        if powerEventWants.swing then
            swingState.registerEvents()
        else
            swingState.unregisterEvents()
        end
        if not powerEventWants.cdg then
            unregisterCdGEvents()
        end
        if powerEventWants.spendPred then
            spendPredState.registerEvents()
        else
            spendPredState.unregisterEvents()
        end
        if powerEventWants.buildPred then
            buildPred.register()
        else
            buildPred.unregister()
        end
    end
    powerEventWants.static = false
    powerEventWants.swing = false
    powerEventWants.cdg = false
    powerEventWants.spendPred = false
    powerEventWants.buildPred = false
end

---Event frame used to listen for talent and spec changes that may alter UnitPowerMax
---or change whether the class/spec even has a secondary resource.
local talentEventFrame = CreateFrame("Frame")

---Debounce handle for UPDATE_SHAPESHIFT_FORM — the event can fire multiple times in
---quick succession during a single form change.
---@type FunctionContainer?
local shapeshiftTimer

---Handles a (debounced) shapeshift form change for non-Feral Druids with druid_cat_form.
local function onShapeshiftFormChanged()
    shapeshiftTimer = nil
    local newPowerType = getActiveResourceTypes()[1]
    if newPowerType ~= playerPowerType then
        powerEventFrame:UnregisterAllEvents()
        unregisterWWEvents()
        unregisterTotsEvents()
        iciclesState.unregisterEvents()
        ironfurState.unregisterEvents()
        unregisterMwEvents()
        unregisterVitalityEvents()
        unregisterIgnorePainEvents()
        hideStackPips()
        shatterState.unregisterEvents()
        swingState.unregisterEvents()
        unregisterCdGEvents()
        spendPredState.unregisterEvents()
        buildPred.unregister()
        playerPowerType = newPowerType
        if getEnabled() and resourcesFrame then
            secondaryResources.Refresh()
        else
            if resourcesFrame then
                resourcesFrame:SetScript("OnUpdate", nil)
                resourcesFrame:Hide()
            end
        end
        private.Anchor.OnComponentStateChange()
    end
end

talentEventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Re-evaluate the secondary power type; specs within a class may differ
        -- (e.g. Arcane mage has ArcaneCharges, Fire/Frost do not).
        local newPowerType = getActiveResourceTypes()[1]
        if newPowerType ~= playerPowerType then
            powerEventFrame:UnregisterAllEvents()
            unregisterWWEvents()
            unregisterTotsEvents()
            iciclesState.unregisterEvents()
            ironfurState.unregisterEvents()
            unregisterMwEvents()
            unregisterVitalityEvents()
            unregisterIgnorePainEvents()
            hideStackPips()
            shatterState.unregisterEvents()
            swingState.unregisterEvents()
            unregisterCdGEvents()
            spendPredState.unregisterEvents()
            buildPred.unregister()
            playerPowerType = newPowerType
        end
        -- Full refresh to show/hide the resource display for the new spec.
        if getEnabled() and resourcesFrame then
            secondaryResources.Refresh()
        else
            if resourcesFrame then
                resourcesFrame:SetScript("OnUpdate", nil)
                resourcesFrame:Hide()
            end
        end
        private.Anchor.OnComponentStateChange()
        return
    end

    -- The resource gate in getActiveResourceTypes reads UnitPowerMax, and with
    -- nothing resolved no power event is registered to see a max appear (or,
    -- for the resolved one, drop to 0). ReevaluatePowerType is a no-op unless
    -- the answer changed.
    if event == "UNIT_MAXPOWER" then
        secondaryResources.ReevaluatePowerType()
        return
    end

    if event == "UPDATE_SHAPESHIFT_FORM" then
        if shapeshiftTimer then
            shapeshiftTimer:Cancel()
        end
        shapeshiftTimer = C_Timer.NewTimer(0.1, onShapeshiftFormChanged)
        return
    end

    if event == "PLAYER_TALENT_UPDATE" then
        -- Fury Warriors: gaining/losing Improved Whirlwind talent changes power type
        -- Paladins: gaining/losing Crusading Strikes changes swing timer eligibility
        local newPowerType = getActiveResourceTypes()[1]
        if newPowerType ~= playerPowerType then
            powerEventFrame:UnregisterAllEvents()
            unregisterWWEvents()
            unregisterTotsEvents()
            iciclesState.unregisterEvents()
            ironfurState.unregisterEvents()
            unregisterMwEvents()
            unregisterVitalityEvents()
            unregisterIgnorePainEvents()
            hideStackPips()
            shatterState.unregisterEvents()
            swingState.unregisterEvents()
            unregisterCdGEvents()
            spendPredState.unregisterEvents()
            buildPred.unregister()
            playerPowerType = newPowerType
            if getEnabled() and resourcesFrame then
                secondaryResources.Refresh()
            else
                if resourcesFrame then
                    resourcesFrame:SetScript("OnUpdate", nil)
                    resourcesFrame:Hide()
                end
            end
            private.Anchor.OnComponentStateChange()
            return
        end
        if getEnabled() and resourcesFrame then
            secondaryResources.Refresh()
        end
        return
    end

    if event == "UPDATE_BONUS_ACTIONBAR" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_IS_GLIDING_CHANGED" or event == "PLAYER_CAN_GLIDE_CHANGED" or event == "CLIENT_SCENE_OPENED" or event == "CLIENT_SCENE_CLOSED" then
        local wasSkyriding = isSkyriding
        isSkyriding = checkSkyriding()
        if wasSkyriding ~= isSkyriding then
            local newPowerType = getActiveResourceTypes()[1]
            if newPowerType ~= playerPowerType then
                powerEventFrame:UnregisterAllEvents()
                unregisterWWEvents()
                unregisterTotsEvents()
                iciclesState.unregisterEvents()
                ironfurState.unregisterEvents()
                unregisterMwEvents()
                unregisterVitalityEvents()
                unregisterIgnorePainEvents()
                hideStackPips()
                shatterState.unregisterEvents()
                swingState.unregisterEvents()
                unregisterCdGEvents()
                spendPredState.unregisterEvents()
                buildPred.unregister()
                playerPowerType = newPowerType
                if getEnabled() and resourcesFrame then
                    secondaryResources.Refresh()
                else
                    if resourcesFrame then
                        resourcesFrame:SetScript("OnUpdate", nil)
                        resourcesFrame:Hide()
                    end
                end
            end
        end
        -- Visibility override changes with mount state (hide on ground mounts,
        -- show always on skyriding); trigger re-layout so the anchoring system
        -- picks up the new override.
        private.Anchor.OnComponentStateChange()
    end
end)

---Creates the parent container frame for secondary resource bars.
---Resource frames are not created here; they are managed dynamically by refreshResourceCount().
secondaryResources.CreateSecondaryResources = function()
    if resourcesFrame then
        error("CreateSecondaryResources() resources frame already exists.")
    end

    local settings = getSettings()
    resourcesFrame = CreateFrame("Frame", "CUE_SecondaryResources", UIParent)
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    if isVertical then
        resourcesFrame:SetSize(settings.height, settings.width)
    else
        resourcesFrame:SetSize(settings.width, settings.height)
    end
    resourcesFrame:SetScript("OnSizeChanged", layoutAllRows)
    resourcesFrame:HookScript("OnShow", auraTap.syncAlpha)
    resourcesFrame:HookScript("OnHide", auraTap.syncAlpha)
    hooksecurefunc(resourcesFrame, "SetAlpha", auraTap.syncAlpha)

    -- Row 1 exists from creation so every pre-rework path — Edit Mode
    -- positioning, an OnSizeChanged before the first Refresh — finds a row to
    -- measure and parent to. It also carries the value text, so nothing more is
    -- built on the component frame itself. Additional rows are created on demand.
    rowFrame = ensureRow(1)
    layoutRows(1)
end

---called from the Init.lua file to initialize the component on PLAYER_LOGIN event
secondaryResources.Initialize = function()
    isSkyriding = checkSkyriding()
    playerPowerType = getActiveResourceTypes()[1]

    -- Always create the container frame so it is available for Edit Mode positioning,
    -- even for classes that have no secondary resource (playerPowerType == nil).
    if not resourcesFrame then
        secondaryResources.CreateSecondaryResources()
    end

    -- Register spec/talent events unconditionally — spec changes can transition the
    -- component between enabled/disabled (e.g. DH Havoc→Vengeance gains a resource).
    -- These must be active from login, not deferred to OnEnable which is never called
    -- during the initial load sequence.
    talentEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    talentEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    talentEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    talentEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    talentEventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    talentEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    talentEventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    talentEventFrame:RegisterEvent("CLIENT_SCENE_OPENED")
    talentEventFrame:RegisterEvent("CLIENT_SCENE_CLOSED")
    talentEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    if select(2, UnitClass("player")) == "DRUID" then
        talentEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    end

    if not getEnabled() then
        resourcesFrame:Hide()
    else
        secondaryResources.Refresh()
    end
end

---Recolors and retextures all active resource bars to match the current profile settings.
---Also re-runs updateComboPointColors for combo-point classes (charged points stay blue).
applyColors = function()
    local r, g, b, a = getCustomResourceColor()
    local hasCustom = r ~= nil
    if not hasCustom then
        r, g, b, a = getResourceColor()
    end
    local settings = getSettings()
    local bgR, bgG, bgB, bgA
    if settings.use_static_background then
        local c = settings.background_color
        bgR, bgG, bgB, bgA = c[1], c[2], c[3], c[4]
    elseif hasCustom or private.profile.resource_colors.use_class_color then
        bgR, bgG, bgB, bgA = r * 0.3, g * 0.3, b * 0.3, 0.8
    else
        bgR, bgG, bgB, bgA = getBackgroundColor()
    end

    local texture = settings.texture
    for i = 1, activeResourceCount do
        local rf = resourceFrames[i]
        applyTexture(rf.bar, texture)
        rf.bar:SetStatusBarColor(r, g, b, a)
        rf.bg:SetColorTexture(bgR, bgG, bgB, bgA)
        private.Util.ApplyBarBorder(rf)
    end
    -- Style Fire Blast recharge overlay bar
    if fbRechargeBar then
        if playerPowerType == SRC.FIRE_BLAST_CHARGES then
            applyTexture(fbRechargeBar, texture)
            fbRechargeBar:SetStatusBarColor(r, g, b, a)
        else
            fbRechargeBar:Hide()
        end
    end
    -- Style Aimed Shot recharge overlay bar
    if asRechargeBar then
        if playerPowerType == SRC.AIMED_SHOT_CHARGES then
            applyTexture(asRechargeBar, texture)
            asRechargeBar:SetStatusBarColor(r, g, b, a)
        else
            asRechargeBar:Hide()
        end
    end
    -- Style the Ignore Pain aura-tap bar. It renders the fill instead of
    -- resourceFrames[1].bar, so it needs the same texture/color — but it is a
    -- bound object, so the write only lands while auras are non-secret; a
    -- mid-combat color change converges on the next out-of-combat pass.
    if ipState.tapBar and not auraTap.blocked() then
        if playerPowerType == SRC.IGNORE_PAIN_PROT then
            applyTexture(ipState.tapBar, texture)
            ipState.tapBar:SetStatusBarColor(r, g, b, a)
        end
    end
    -- Same for the stack strips' pip taps (Sweeping Strikes / Teachings): they
    -- render the fill instead of resourceFrames[i].bar. Gated before the closure
    -- so the in-combat path allocates nothing.
    if not auraTap.blocked() then
        local pipKey, _, n = stackPipSpec()
        if pipKey then
            -- Every writer of a pip's colour must consult the threshold override,
            -- exactly as the build closure in updateStackPips does. This pass runs on
            -- every Refresh and used to flat-write the flat resource colour, so a
            -- Tier C colour survived only until the first applyColors after its build
            -- -- i.e. was never seen. Same rule as the viewer-child alpha writers in
            -- `.context/patterns.md`: writer order must not decide the result.
            local base = STACK_STRIPS[playerPowerType].base
            local isPrimary = rowIndex == 1 and activeResourceTypes.hasPrimary
            local segmented = n > 1
            auraTap.stylePips(pipKey, function(bar, i)
                local pc
                if segmented then
                    local tr, tg, tb, ta = stackThresholdColor(base, isPrimary, i)
                    if tr then pc = { tr, tg, tb, ta } end
                end
                applyPipColor(bar, pc, texture, r, g, b, a)
            end)
        end
    end
    -- Style Radiance recharge overlay bar
    if radRechargeBar then
        if playerPowerType == SRC.RADIANCE_CHARGES then
            applyTexture(radRechargeBar, texture)
            radRechargeBar:SetStatusBarColor(r, g, b, a)
        else
            radRechargeBar:Hide()
        end
    end
    if playerPowerType == Enum.PowerType.ComboPoints then
        updateComboPointColors()
        cdgState.updateDisplay()
    end
    -- Re-apply threshold highlight on filled 5+ Maelstrom Weapon segments
    if playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        mwState.updateChargeDisplay()
    end
    -- Re-apply lighter color on the swing fill segment
    if swingState.fillIndex and swingState.fillIndex <= activeResourceCount then
        local swR, swG, swB, swA = getSwingTimerColor()
        resourceFrames[swingState.fillIndex].bar:SetStatusBarColor(swR, swG, swB, swA)
    end
    -- Re-apply the Divine Purpose tint on the filled Holy Power pips
    applyDivinePurposeTint()
    -- Re-apply the Unbound Flame expiry border on the Devastation extra row
    applyUnboundFlameExpiry()
    -- Re-apply spend prediction overlay on Soul Shard segments
    spendPredState.apply()
    -- Re-apply builder prediction overlay on empty segments
    buildPred.apply()
    -- Generic per-spec threshold color overrides (Tier A — public counts)
    applyThresholdColors()
    -- Tier B — secret-backed resources fold thresholds via EvaluateColorFromBoolean,
    -- using the just-applied base color (r,g,b,a) from getCustomResourceColor.
    if playerPowerType == SRC.FIRE_BLAST_CHARGES then
        applyThresholdColorsSecret(cachedFireBlastCharges, CreateColor(r, g, b, a))
    elseif playerPowerType == SRC.AIMED_SHOT_CHARGES then
        applyThresholdColorsSecret(cachedAimedShotCharges, CreateColor(r, g, b, a))
    elseif playerPowerType == SRC.RADIANCE_CHARGES then
        applyThresholdColorsSecret(cachedRadianceCharges, CreateColor(r, g, b, a))
    elseif playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        applyThresholdColorsSecret(cachedVengeanceFragments, CreateColor(r, g, b, a))
    end
    -- Breakpoint pip fill-color curves override the base color per power
    -- tick; re-assert immediately so a color re-apply doesn't flash the base.
    if SRC.continuousBarPowers[playerPowerType] then
        private.BreakpointPips.UpdateDynamic(continuousPipHost)
    end
end

-- ── Resource Threshold Colors ───────────────────────────────────────────────

---Returns the per-spec threshold list key, or nil when spec is unknown.
---@return string?
local function getThresholdSpecKey()
    local _, class = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not class or not specIndex then return nil end
    return class .. "-" .. specIndex
end

---Returns whether thresholds are active for the given spec key. Requires BOTH
---the global master toggle to be on AND the per-spec override to be enabled
---(missing per-spec entry is treated as enabled so new specs opt in by default).
---Tolerates legacy boolean shape on resource_thresholds_enabled from profiles
---saved before the per-spec rework.
---@param specKey string?
---@return boolean
local function isThresholdEnabledForSpec(specKey)
    if not specKey then return false end
    local settings = getSettings()
    if settings.resource_thresholds_global_enabled == false then return false end
    local field = settings.resource_thresholds_enabled
    if field == nil then return true end
    if type(field) == "boolean" then return field end
    if type(field) ~= "table" then return true end
    local v = field[specKey]
    if v == nil then return true end
    return v and true or false
end

---Returns true when the active display reads from a secret-tainted source.
---SpellChargeInfo-backed Fire Blast / Aimed Shot are secret; Vengeance Soul
---Fragments are also treated as secret (uses GetSpellCastCount, existing code
---comments mark the count as secret). Every other resource (UnitPower, runes,
---and GetPlayerAuraBySpellID + diff-cache counts) is public and uses Tier A.
isSecretBackedResource = function()
    return playerPowerType == SRC.FIRE_BLAST_CHARGES
        or playerPowerType == SRC.AIMED_SHOT_CHARGES
        or playerPowerType == SRC.RADIANCE_CHARGES
        or playerPowerType == SRC.SOUL_FRAG_VENGEANCE
        or STACK_STRIPS[playerPowerType] ~= nil
end

---Returns the public integer count of filled segments for the current display
---mode, or nil when the active resource is Tier B (secret) or a fill bar
---(Stagger / Vitality / Vigor / swing timers / Ironfur / Ignore Pain).
getCurrentResourceCount = function()
    if isSecretBackedResource() then return nil end
    if playerPowerType == Enum.PowerType.ComboPoints then
        return SRC.staticPower(Enum.PowerType.ComboPoints)
    elseif playerPowerType == Enum.PowerType.HolyPower then
        return UnitPower("player", Enum.PowerType.HolyPower)
    elseif playerPowerType == Enum.PowerType.SoulShards then
        local shardPower = UnitPower("player", Enum.PowerType.SoulShards, true)
        local shardModifier = UnitPowerDisplayMod(Enum.PowerType.SoulShards)
        return (shardModifier ~= 0) and math.floor(shardPower / shardModifier) or 0
    elseif playerPowerType == Enum.PowerType.Chi then
        return UnitPower("player", Enum.PowerType.Chi)
    elseif playerPowerType == Enum.PowerType.ArcaneCharges then
        return UnitPower("player", Enum.PowerType.ArcaneCharges)
    elseif playerPowerType == Enum.PowerType.Essence then
        return UnitPower("player", Enum.PowerType.Essence)
    elseif playerPowerType == Enum.PowerType.Runes then
        local ready = 0
        for i = 1, 6 do
            if runeState.startTimes[i] == nil then ready = ready + 1 end
        end
        return ready
    elseif playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        return mwState.charges
    elseif playerPowerType == SRC.WW_CHARGES_FURY then
        return wwState.charges
    elseif playerPowerType == SRC.TOTS_CHARGES_SURVIVAL then
        return totsState.charges
    elseif playerPowerType == SRC.ICICLES_FROST then
        return iciclesState.count
    end
    -- SOUL_FRAG_VENGEANCE is secret (Tier B, handled via applyThresholdColorsSecret).
    -- SOUL_FRAG_DEVOURER is a single fill bar (no discrete segments) — excluded.
    -- Fill bars (Stagger, Vitality, Vigor, Ironfur, Ignore Pain) also fall through.
    return nil
end

---Tier C — the threshold color for pip `i` of the stack strip `base`, or nil to leave
---the pip on the strip's flat resource color.
---
---Stack strips carry no count this code can read (the aura is secret and the engine
---drives the fill). What IS knowable is the pip's own index, and the engine shows pip
---`i` only once stacks reach `i` — so a per-pip colour can gate on "the count reached
---THIS pip" and on nothing else.
---
---**`single` therefore works exactly, and the other two do not.** Colouring only pip
---`value` lights at the threshold and never before. `all_previous` and `all` both ask
---for pips BELOW the threshold, and a pip index cannot gate those: colouring pip 1 for
---a threshold of 12 would light the threshold colour at one stack. Those two fall back
---to "from this stack upward" (every pip at or above `value`), which is the honest
---approximation — it can never colour a pip the player has not earned. The animated
---border has no such limit and honours all three, because a border window's reveal is
---`applications >= value` wherever the window sits — see `stackThresholdRuns`.
---
---Highest matching threshold wins, matching the "higher overwrites lower" rule the
---segment paths get from their ascending sort.
---`isPrimary` is what lets a strip that IS the spec's primary — Sweeping Strikes,
---Teachings, Art of the Glaive on Havoc — answer to a `resource = nil` entry, since nil
---means "the primary row" rather than "a non-strip resource". Those three had no working
---thresholds at all before Tier C existed (classified secret, never dispatched), so this
---gains them rather than changing anything.
---@param base string  the STACK_STRIPS `base` id of the strip being drawn
---@param isPrimary boolean  true when this strip occupies row 1 as the spec's primary
---@param i integer  1-based pip index
---@return number? r, number? g, number? b, number? a
stackThresholdColor = function(base, isPrimary, i)
    local key = getThresholdSpecKey()
    if not key then return end
    if not isThresholdEnabledForSpec(key) then return end
    local list = getSettings().resource_thresholds
    list = list and list[key]
    if not list then return end
    local best, bestValue
    for n = 1, #list do
        local t = list[n]
        local value = t.value or 0
        -- `single` is the ONE mode a per-pip colour can honour exactly: pip `value`
        -- renders only once the count reaches `value`, so colouring just that pip lights
        -- at the threshold and never before. The other two ask for pips BELOW the
        -- threshold, which a pip index cannot gate — see the note above.
        local claims = (t.mode == "single") and (i == value) or (t.mode ~= "single" and i >= value)
        if (t.resource == base or (isPrimary and t.resource == nil))
            and value > 0 and claims
            and (not bestValue or value > bestValue) then
            best, bestValue = t, value
        end
    end
    if not best or not best.color then return end
    local c = best.color
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

---A cheap numeric fingerprint of every threshold scoped to stack strip `base`, used by
---updateStackPips to notice that a rebuild is needed.
---
---Tier C bakes its colors into the pip bars at BUILD time, so an edit is invisible until
---the set rebuilds -- and the build guard only watches the pip count and the cap. Rather
---than have each editing surface announce itself (the Options add/remove buttons already
---forget the profile-switch path, which fires no threshold callback at all), the consumer
---diffs. Same shape as IconTracker's slotStyle* fields and the aura trackers'
---lastRestyleGeom; see `.context/patterns.md`.
---
---Allocation-free and order-independent -- entries are summed, not concatenated, so a
---list rebuilt in a different order does not force a spurious rebuild.
---@param base string
---@param isPrimary boolean
---@return number
stackThresholdSig = function(base, isPrimary)
    local key = getThresholdSpecKey()
    if not key or not isThresholdEnabledForSpec(key) then return 0 end
    local list = getSettings().resource_thresholds
    list = list and list[key]
    if not list then return 0 end
    local sig = 0
    for n = 1, #list do
        local t = list[n]
        if t.resource == base or (isPrimary and t.resource == nil) then
            local c = t.color
            -- `mode` shapes the border's runs (see stackThresholdRuns), so an edit that
            -- changes only the mode still has to force a rebuild. The pip recolour
            -- ignores mode, but this signature serves both.
            local m = (t.mode == "single" and 1) or (t.mode == "all" and 2) or 3
            sig = sig + (t.value or 0) * 7919 + m * 104729
                + ((c and c[1] or 0) + (c and c[2] or 0) * 3 + (c and c[3] or 0) * 7
                    + (c and c[4] or 1) * 11) * 131
        end
    end
    return sig
end

---Slices the strip into one border run per threshold, ascending, or nil when the strip
---has none. Boundaries are in PIP units (0 .. cap) and scaled to pixels by
---`auraTap.layoutBorder`, so a resize never needs a rebuild.
---
---**The border honours `mode`, and the pip recolour cannot.** That asymmetry is the whole
---reason this function exists separately from `stackThresholdColor`. A pip's colour can
---only ever say "stacks reached THIS pip", so `all_previous` would light pip 1 in the
---12-threshold's colour at one stack — which is why Tier C ignores mode. A border window
---is not bound that way: its reveal is `applications >= value` wherever the window sits,
---so the window can be one segment, the stretch below the threshold, or the whole bar,
---and still light at exactly the right count.
---
---  single        the threshold's own segment
---  all_previous  from the previous threshold up to this one
---  all           everything from the previous threshold to the cap
---
---**A run stops at its own threshold** (except `all`). Running on to the NEXT threshold's
---boundary was the first cut and it bordered segments that are still empty: at 6 of a
---6/12 pair the border reached pip 11, outlining five pips the player had not earned.
---
---**Runs are carved in ascending order against a watermark**, so they can never overlap
---whatever the modes are — an `all` entry claims the rest of the bar and any threshold
---above it collapses to nothing and is dropped. Overlap is not cosmetic here: additive
---edges sum instead of overriding, and the pulse takes alpha below 1 so a lower layer
---bleeds through the upper.
---
---Allocates, so it is called only when `stackThresholdSig` says the list moved.
---@param base string
---@param isPrimary boolean
---@param cap integer
---@return table[]?  { { value, color, mode, start, stop } } ascending by value
stackThresholdRuns = function(base, isPrimary, cap)
    local key = getThresholdSpecKey()
    if not key or not isThresholdEnabledForSpec(key) then return end
    local list = getSettings().resource_thresholds
    list = list and list[key]
    if not list then return end
    local out
    for n = 1, #list do
        local t = list[n]
        local value = t.value or 0
        -- A threshold at or above the cap can never be reached, and one without a colour
        -- has nothing to draw. Both are silently skipped rather than drawn dark.
        if (t.resource == base or (isPrimary and t.resource == nil))
            and value > 0 and value <= cap and t.color then
            out = out or {}
            -- Strip entries saved before the border existed were forced to "single" by
            -- the Options Add button. Anything genuinely missing a mode gets the stretch
            -- shape, which is what the border shipped with.
            out[#out + 1] = { value = value, color = t.color, mode = t.mode or "all_previous" }
        end
    end
    if not out then return end
    table.sort(out, function(x, y) return x.value < y.value end)
    local water = 0
    for m = 1, #out do
        local mode = out[m].mode
        -- `single` starts at its own segment, the other two continue from wherever the
        -- last run ended. Clamping to the watermark is what keeps an `all` entry below
        -- them from being overdrawn.
        out[m].start = (mode == "single") and math.max(water, out[m].value - 1) or water
        out[m].stop = (mode == "all") and cap or out[m].value
        water = out[m].stop
    end
    -- Collapsed runs: a duplicate value, or any threshold sitting above an `all` entry
    -- that already claimed the rest of the bar. A zero-width edge drawn on top of its
    -- twin is the overlap this whole design exists to avoid, so drop them.
    for m = #out, 1, -1 do
        if out[m].stop <= out[m].start then table.remove(out, m) end
    end
    return (#out > 0) and out or nil
end

---Applies per-spec threshold color overrides to the segment bars.
---Runs as the tail of applyColors and after each Tier A update function
---that sets segment values directly (UNIT_AURA event paths).
---Early-returns cheaply when no thresholds are configured for the current spec.
applyThresholdColors = function()
    local key = getThresholdSpecKey()
    if not key then return end
    if not isThresholdEnabledForSpec(key) then return end
    local list = getSettings().resource_thresholds
    list = list and list[key]
    if not list or #list == 0 then return end
    local count = getCurrentResourceCount()
    -- This pass only ever paints: a segment whose threshold is no longer met keeps
    -- the colour until something rewrites the base. So a drop in count re-runs
    -- applyColors, which writes the base and then calls this again last. Cleared
    -- before the call, so that nested call paints instead of recursing.
    local row = rows[rowIndex]
    if row.thresholdLit and (count or 0) < row.thresholdLit then
        row.thresholdLit = nil
        applyColors()
        return
    end
    if not count or count <= 0 then return end
    if activeResourceCount == 0 then return end

    -- Local sorted copy (ascending by value) so higher thresholds overwrite
    -- lower ones when they overlap, matching the "higher wins" rule.
    -- Entries carrying a `resource` belong to an extra stack-strip row and are
    -- drawn per-pip by updateStackPips, not here: this function only ever sees
    -- the row it was called under, and only the primary row has a public count.
    -- Without the skip the whole per-spec list lands on the primary, which is
    -- what made a Shatter threshold recolor the Icicles bar.
    local sorted = {}
    for i = 1, #list do
        if list[i].resource == nil then sorted[#sorted + 1] = list[i] end
    end
    if #sorted == 0 then return end
    table.sort(sorted, function(a, b) return (a.value or 0) < (b.value or 0) end)

    local lit
    for i = 1, #sorted do
        local t = sorted[i]
        local value = t.value or 0
        if value > 0 and count >= value then
            local c = t.color
            if c then
                lit = count
                local r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                if t.mode == "single" then
                    local f = resourceFrames[value]
                    if f and f.bar then f.bar:SetStatusBarColor(r, g, b, a) end
                elseif t.mode == "all_previous" then
                    local limit = math.min(value, activeResourceCount)
                    for seg = 1, limit do
                        local f = resourceFrames[seg]
                        if f and f.bar then f.bar:SetStatusBarColor(r, g, b, a) end
                    end
                else  -- "all" (and any unknown mode defaults to all, matching Tier B behavior)
                    local limit = math.min(count, activeResourceCount)
                    for seg = 1, limit do
                        local f = resourceFrames[seg]
                        if f and f.bar then f.bar:SetStatusBarColor(r, g, b, a) end
                    end
                end
            end
        end
    end
    row.thresholdLit = lit
end

---Tier B variant for SpellChargeInfo-backed resources (Fire Blast, Aimed Shot).
---The charge count is secret; comparisons `secretCount >= i` produce a secret
---bool which is fed ONLY into C_CurveUtil.EvaluateColorFromBoolean (AllowedWhenTainted).
---The returned ColorMixin is unpacked into SetStatusBarColor.
---Only the "all" mode is honored — the Options UI gates secret resources to
---that mode, and any stale single/all_previous entries are silently ignored.
---@param secretCount any  secret-tainted integer (e.g. cachedFireBlastCharges)
---@param baseColorObj table?  ColorMixin for the resource's normal color; nil → default white
applyThresholdColorsSecret = function(secretCount, baseColorObj)
    local key = getThresholdSpecKey()
    if not key then return end
    if not isThresholdEnabledForSpec(key) then return end
    local list = getSettings().resource_thresholds
    list = list and list[key]
    if not list or #list == 0 then return end
    if activeResourceCount == 0 then return end

    -- Filter to "all"-mode entries, sorted ascending so higher values run last
    -- and overwrite lower-value hits on overlapping segments.
    -- `resource ~= nil` scopes an entry to an extra stack-strip row, which draws
    -- its own thresholds per-pip; same reason as applyThresholdColors.
    local sorted = {}
    for i = 1, #list do
        if list[i].mode == "all" and list[i].resource == nil then
            sorted[#sorted + 1] = list[i]
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted, function(a, b) return (a.value or 0) < (b.value or 0) end)

    -- Pre-build ColorMixins per threshold; cache on the threshold table so
    -- reallocation only happens when the entry's color array changes.
    for i = 1, #sorted do
        local t = sorted[i]
        if not t.__colorObj then
            local c = t.color or {1, 1, 1, 1}
            t.__colorObj = CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    end

    local base = baseColorObj or CreateColor(1, 1, 1, 1)
    for seg = 1, activeResourceCount do
        local color = base
        for i = 1, #sorted do
            local t = sorted[i]
            local value = t.value or 0
            if value > 0 then
                -- ONE comparison, never two joined by and/or: `and` would perform
                -- a boolean test on the left side's secret result, which throws
                -- ("attempt to perform boolean test on a secret boolean value").
                -- (c >= a) and (c >= b) is equivalent to c >= max(a, b).
                -- The secret-tainted bool then flows only into
                -- EvaluateColorFromBoolean (AllowedWhenTainted).
                local hit = secretCount >= math.max(seg, value)
                color = C_CurveUtil.EvaluateColorFromBoolean(hit, t.__colorObj, color)
            end
        end
        resourceFrames[seg].bar:SetStatusBarColor(color:GetRGBA())
    end
end

---Invalidates the cached ColorMixins on threshold entries after Options edits
---or profile reloads, so the next apply rebuilds them from the updated color[].
local function invalidateThresholdColorCache()
    local list = getSettings().resource_thresholds
    if not list then return end
    for _, specList in pairs(list) do
        if type(specList) == "table" then
            for i = 1, #specList do specList[i].__colorObj = nil end
        end
    end
end
private._sr.invalidateThresholdColorCache = invalidateThresholdColorCache

---Exposes the classifier for the Options UI so it can dynamically gate the
---mode dropdown to "all" only when the active resource is secret-backed.
---@return boolean
private._sr.IsSecretBackedResource = function()
    return isSecretBackedResource()
end

---Exposes the rows a threshold can be scoped to, so the Options picker offers exactly
---what is on screen for this spec rather than a static per-class list.
---
---`id` is what lands in `resource_threshold.resource`: nil for row 1 (the primary),
---otherwise the strip's `base` -- row 1 included when it holds an extra because the
---primary is switched off, so a threshold set then stays with its strip. `isStrip`
---tells the panel which entries are Tier C — those ignore `mode` and color from the
---chosen stack upward, so the mode dropdown is meaningless for them. Row 1 can be a strip too (Sweeping Strikes, Teachings, Art of
---the Glaive on Havoc), which is why `isStrip` is reported separately from `id`.
---
---`labelKey` rather than a resolved string: the locale table is the Options layer's,
---and handing back a key keeps this component free of it.
---@return table[]  { { id = string?, labelKey = string?, isStrip = boolean } }
private._sr.GetThresholdResources = function()
    local out = {}
    for i = 1, activeRowCount do
        local row = rows[i]
        local strip = row and row.powerType and STACK_STRIPS[row.powerType]
        if i == 1 and activeResourceTypes.hasPrimary then
            out[#out + 1] = {
                id = nil,
                labelKey = strip and strip.labelKey or nil,
                isStrip = strip ~= nil,
            }
        elseif strip then
            out[#out + 1] = { id = strip.base, labelKey = strip.labelKey, isStrip = true }
        end
    end
    return out
end

secondaryResources.GetFrame = function()
    return resourcesFrame
end

---One active row's share of a Refresh: registers that row's events, sizes its
---segment pool, runs its resource's display path, recolors it and updates its
---value text — in exactly the order the single-resource Refresh ran them.
---
---Runs under `withRow`, so every `playerPowerType` / `resourceFrames` /
---`activeResourceCount` / `rowFrame` read inside is that row's own and the
---per-resource bodies work unchanged. The `resourcesFrame:SetScript("OnUpdate")`
---writes below are still component-wide: an OnUpdate-driven resource therefore
---has to be the only one of its kind on screen, which the single-row resolver
---guarantees today.
local refreshRow = function()
    registerPowerEvents()
    refreshResourceCount()

    if playerPowerType == SRC.WW_CHARGES_FURY then
        wwState.updateChargeDisplay()
        if wwState.charges > 0 and wwState.expiresAt then
            resourcesFrame:SetScript("OnUpdate", wwState.onUpdate)
        end
    elseif playerPowerType == SRC.TOTS_CHARGES_SURVIVAL then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(SRC.TOTS_AURA_ID)
        totsState.charges = aura and aura.applications or 0
        totsState.updateChargeDisplay()
    elseif playerPowerType == SRC.ICICLES_FROST then
        iciclesState.refresh()
    elseif playerPowerType == SRC.IRONFUR_GUARDIAN then
        -- Aura is secret — display relies entirely on cast events.
        -- Re-apply bar + ticks if instances are still active after a Refresh cycle.
        ironfurState.applyBarAndTicks()
        if #ironfurState.instances > 0 then
            resourcesFrame:SetScript("OnUpdate", ironfurState.onUpdate)
        end
    elseif playerPowerType == SRC.MW_CHARGES_ENHANCEMENT then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(mwState.variant.aura)
        mwState.charges = aura and aura.applications or 0
        mwState.updateChargeDisplay()
    elseif playerPowerType == SRC.FIRE_BLAST_CHARGES then
        updateFireBlastCharges()
    elseif playerPowerType == SRC.AIMED_SHOT_CHARGES then
        updateAimedShotCharges()
        applyLockAndLoadGlow()
    elseif playerPowerType == SRC.RADIANCE_CHARGES then
        updateRadianceCharges()
    elseif playerPowerType == SRC.SOUL_FRAG_VENGEANCE then
        updateVengeanceSoulFragments()
    elseif playerPowerType == SRC.SOUL_FRAG_DEVOURER then
        refreshDevourerMax()
        updateDevourerSoulFragments()
    elseif playerPowerType == SRC.STAGGER_BREWMASTER then
        layoutStaggerPips()
        updateStaggerBar()
    elseif playerPowerType == SRC.VITALITY_MONK then
        refreshVitalityMax()
        updateVitalityBar()
    elseif playerPowerType == SRC.IGNORE_PAIN_PROT then
        ipState.updateBar()
    elseif STACK_STRIPS[playerPowerType] then
        updateStackPips()
    elseif playerPowerType == SRC.SKYRIDING_VIGOR then
        refreshVigorValues()
        refreshVigorThrillState()
        resourcesFrame:SetScript("OnUpdate", onUpdateVigor)
    elseif SRC.continuousBarPowers[playerPowerType] then
        updateContinuousBar()
    elseif playerPowerType == Enum.PowerType.Runes then
        if runeState.refreshValues() then
            resourcesFrame:SetScript("OnUpdate", runeState.onUpdate)
        end
    elseif playerPowerType == Enum.PowerType.Essence then
        refreshEssenceBaseCost()
        augID.install()
        refreshEssenceBurstState()
        if refreshEssenceValues() then
            resourcesFrame:SetScript("OnUpdate", onUpdateEssence)
        end
    else
        updateResourceValues()
        if playerPowerType == Enum.PowerType.ComboPoints then
            updateComboPointColors()
        end
        if playerPowerType == Enum.PowerType.HolyPower then
            if swingState.startTime then
                swingState.updateBars()
            end
            applyDivinePurposeTint()
        end
    end

    applyColors()
    cdgState.updateDisplay()

    -- Apply value text font settings and update the displayed value
    local valueFont = getSettings().value_font
    if valueFont and rowFrame.valueText and private.fontsDirty then
        private.Util.ApplyFontProfile(rowFrame.valueText, valueFont, rowFrame)
        -- Mirror the full value-font profile onto the bound tap FS (write is
        -- forbidden while auras are secret; a mid-combat font change converges
        -- on the next non-secret font pass), then invalidate the seam so the
        -- following updateValueText re-derives it from the fresh profile
        -- anchor (ApplyFontProfile just repositioned both FontStrings).
        -- The bound tap FS is only writable while auras are non-secret; when
        -- blocked, mark it dirty so updateValueText re-applies on the first
        -- writable tick (fontsDirty passes only run on config changes, so
        -- "wait for the next pass" would never converge).
        -- Row-1 only, like every other reapFc writer: this block runs once per
        -- row, and `applyTapAnchors`' restore is gated on `seamApplied`. A row-2
        -- pass clearing it after row 1 re-derived it leaves the flag false while
        -- row 1's valueText is physically at the seam position, so the next
        -- `applyTapAnchors(false)` skips its restore and the anchor stays wrong
        -- until the following fonts pass. Before the row guards existed, row 2's
        -- own unguarded `applyTapAnchors(false)` repaired that by accident.
        -- `tapFontDirty` is inside the guard for consistency rather than for a
        -- defect: it is monotone and its consumer is already row-1-gated, but a
        -- row-2 set would survive every fonts pass with nothing to consume it,
        -- costing one redundant idempotent applyTapFont.
        if rowIndex == 1 then
            if reapFc.tapStacks then
                reapFc.tapFontDirty = true
            end
            -- Re-derive the seam from the fresh profile anchor on the next tick.
            reapFc.seamApplied = false
        end
        -- Same for the Ignore Pain tap FS (marks itself dirty when blocked).
        ipState.applyTapFont()
        -- And for the stack strips' count FS (same dirty-on-blocked contract).
        -- Owning row only. `applyStackTapFont` anchors the SHARED `stackTap.text`
        -- to the current `rowFrame`, so an unguarded per-row call is last-writer-
        -- wins: it lands correctly today purely because rows run ascending and the
        -- readout-bearing strip is the last row. That is the same accident the
        -- reapFc guards above removed, so close it the same way rather than
        -- leaving it resting on row order.
        if stackTap.rowIndex == rowIndex then
            applyStackTapFont()
        end
        if (getSettings().orientation or "horizontal") == "vertical" then
            private.Util.ApplyVerticalFontRotation(rowFrame.valueText)
        else
            rowFrame.valueText:SetRotation(0)
        end
    end
    updateValueText()
end

secondaryResources.Refresh = function()
    if not getSettings().enabled then
        if resourcesFrame then
            resourcesFrame:Hide()
        end
        return
    end

    local types, count = getActiveResourceTypes()

    -- A resource change is a transition, not something Refresh may absorb.
    -- syncRows would write the new type into row 1 and withRow would publish it
    -- straight into playerPowerType, skipping the teardown that unregisters the
    -- OUTGOING resource's events and clears its pip strip — reachable from a
    -- profile apply, which refreshes every component. ReevaluatePowerType owns
    -- that teardown; it assigns the new type before calling back in here, so the
    -- re-entrant Refresh takes the false side of this test and proceeds.
    --
    -- Ahead of the "nothing to show" gate below: an extra's setter calls Refresh,
    -- and with no primary (Shatter with Icicles off) playerPowerType is nil until
    -- this transition assigns the extra to it.
    if types[1] ~= playerPowerType then
        secondaryResources.ReevaluatePowerType()
        return
    end
    if count == 0 then
        if resourcesFrame then
            resourcesFrame:Hide()
        end
        return
    end

    if not resourcesFrame then
        secondaryResources.CreateSecondaryResources()
    end

    local settings = getSettings()
    barInterpolation = settings.bar_smoothing and Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate

    -- Apply swapped dimensions before layoutBars runs via refreshResourceCount.
    -- When the anchor system owns the width (cueAnchorOwnsWidth), only update
    -- height so the anchored width isn't overridden with settings.width.
    local isVertical = (settings.orientation or "horizontal") == "vertical"
    if resourcesFrame.cueAnchorOwnsWidth then
        if isVertical then
            resourcesFrame:SetHeight(settings.width)
        else
            resourcesFrame:SetHeight(settings.height)
        end
    else
        if isVertical then
            resourcesFrame:SetSize(settings.height, settings.width)
        else
            resourcesFrame:SetSize(settings.width, settings.height)
        end
    end

    -- Clear any stale OnUpdate (e.g. onUpdateVigor) before switching resource types.
    -- Each branch below re-applies the correct OnUpdate if needed.
    resourcesFrame:SetScript("OnUpdate", nil)

    syncRows(types, count)

    for i = 1, count do
        withRow(i, refreshRow)
    end
    -- One application of the union, after every row has decided.
    applyPowerEventRegistrations()

    -- Only show when the anchor chain root is visible (e.g. Blizzard's CooldownViewer is
    -- shown). Without this guard, event-triggered refreshes would re-show the frame after
    -- the anchoring system hid it due to a hidden root ancestor. Any row with segments
    -- keeps the component on screen; a row that ended up empty simply draws nothing.
    local totalSegments = 0
    for i = 1, count do
        totalSegments = totalSegments + rows[i].count
    end
    if totalSegments > 0 and private.Anchor.IsVisibleForComponent(secondaryResources.name) then
        resourcesFrame:Show()
    else
        resourcesFrame:Hide()
    end
end

secondaryResources.OnEnable = function()
    talentEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    talentEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    talentEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    talentEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    talentEventFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
    talentEventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    talentEventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    talentEventFrame:RegisterEvent("CLIENT_SCENE_OPENED")
    talentEventFrame:RegisterEvent("CLIENT_SCENE_CLOSED")
    talentEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    if select(2, UnitClass("player")) == "DRUID" then
        talentEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    end
    isSkyriding = checkSkyriding()
    secondaryResources.Refresh()
end

secondaryResources.OnDisable = function()
    powerEventFrame:UnregisterAllEvents()
    unregisterWWEvents()
    unregisterTotsEvents()
    iciclesState.unregisterEvents()
    ironfurState.unregisterEvents()
    unregisterMwEvents()
    unregisterVitalityEvents()
    unregisterIgnorePainEvents()
    hideStackPips()
    shatterState.unregisterEvents()
    swingState.unregisterEvents()
    unregisterCdGEvents()
    spendPredState.unregisterEvents()
    buildPred.unregister()
    -- The Essence Burst tap needs a UNIT_AURA tick to re-query cost, so
    -- augID.tracker now registers one unconditionally; leaving it live on a
    -- disabled component would markDirty on every player aura change. Its only
    -- previous caller was the /cue ebtap switch, which is why this was never
    -- wired up. Refresh's Essence branch re-installs on re-enable.
    augID.uninstall()
    -- Keep talentEventFrame events registered — PLAYER_SPECIALIZATION_CHANGED must
    -- stay active so spec changes can re-enable the component (e.g. Havoc→Vengeance).
    if shapeshiftTimer then
        shapeshiftTimer:Cancel()
        shapeshiftTimer = nil
    end
    private.essenceStartTime = nil  -- fresh anchor on next re-enable; essenceFillDuration carries over
    private.hasteDirty = true       -- force a fresh haste sample on next enable
    for _, border in pairs(essencePred.borders) do border:Hide() end
    vigorState.startTime = nil    -- ensure initial sync via cooldown progress on next re-enable
    -- The soul-fragment count's container follows resourcesFrame:Hide() below
    -- through auraTap.syncAlpha's hooks.
    reapFc.stopCapPoll()
    if resourcesFrame then
        resourcesFrame:SetScript("OnUpdate", nil)
        resourcesFrame:Hide()
    end
end

---Re-evaluates the secondary power type and refreshes or hides the display.
---Called from option toggles (e.g. brewmaster_stagger) that change which
---resource type is active without a spec or shapeshift change.
secondaryResources.ReevaluatePowerType = function()
    local newPowerType = getActiveResourceTypes()[1]
    if newPowerType ~= playerPowerType then
        powerEventFrame:UnregisterAllEvents()
        unregisterWWEvents()
        unregisterTotsEvents()
        iciclesState.unregisterEvents()
        ironfurState.unregisterEvents()
        unregisterMwEvents()
        unregisterVitalityEvents()
        unregisterIgnorePainEvents()
        hideStackPips()
        shatterState.unregisterEvents()
        swingState.unregisterEvents()
        unregisterCdGEvents()
        spendPredState.unregisterEvents()
        buildPred.unregister()
        playerPowerType = newPowerType
        if getEnabled() and resourcesFrame then
            secondaryResources.Refresh()
        else
            if resourcesFrame then
                resourcesFrame:SetScript("OnUpdate", nil)
                resourcesFrame:Hide()
            end
        end
        private.Anchor.OnComponentStateChange()
    end
end

secondaryResources.GetComponentName = function()
    return secondaryResources.name
end

secondaryResources.GetComponentSize = function()
    local settings = getSettings()
    -- Cross axis grows with the extra rows rather than being divided among
    -- them, so the primary keeps its configured height — see crossAxisSpan.
    local cross = crossAxisSpan()
    if (settings.orientation or "horizontal") == "vertical" then
        return cross, settings.width
    end
    return settings.width, cross
end

private.SecondaryResources = secondaryResources
private.ComponentManager.RegisterComponent("SecondaryResources", secondaryResources)
