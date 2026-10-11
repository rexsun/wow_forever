
--[[
    ConsumableTracker component.
    Displays cooldown icons for consumable items (combat potions, health potions,
    mana potions, healthstones) the player has in their bags. Each icon shows the
    item texture, a cooldown sweep overlay, and an optional item count.

    Items are organised into families — multiple ranks of the same potion share
    a cooldown, so only one icon is shown per family using the highest-rank item
    the player possesses. Families are defined in CONSUMABLE_FAMILIES and
    individually togglable via the tracked_families profile setting. Display
    names are fetched from item info (C_Item.GetItemNameByID) for localization.

    Categories control runtime behaviour:
    - combat: shows all tracked families individually (each has a unique effect)
    - health: "best only" — shows a single icon for the best health potion
    - mana:   "best only" — shows a single icon for the best mana potion;
              auto-hidden for non-healer specs when profile.auto_hide is true
    - healthstone: shows all tracked healthstone families individually
    - utility: shows all tracked utility families individually (drums, battle-res)
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field ConsumableTracker consumabletracker

---@class consumabletracker : component

---@type consumabletracker
---@diagnostic disable-next-line: missing-fields
local consumableTracker = {}

consumableTracker.name = "ConsumableTracker"

-- ---------------------------------------------------------------------------
-- Consumable family registry
-- ---------------------------------------------------------------------------

---@class consumable_family
---@field key string       unique family key stored in tracked_families
---@field category string  "combat"|"health"|"mana"|"healthstone"|"utility"
---@field itemIds number[] fleeting (cauldron) variants first, then ranks ascending; the last entry names the family and is scanned first

-- One list per game client (#27), picked at load: the items differ, and a
-- shared list would fill every client's Options panel with the others' potions.

---@type consumable_family[]
local RETAIL_FAMILIES = {
    -- === Midnight Combat Potions ===
    { key = "lights_potential",           category = "combat",  itemIds = {245897, 245898, 241309, 241308},    icon = C_Item.GetItemIconByID(241309) },
    { key = "draught_of_rampant_abandon", category = "combat",  itemIds = {245911, 245910, 241293, 241292},    icon = C_Item.GetItemIconByID(241293) },
    { key = "potion_of_recklessness",     category = "combat",  itemIds = {245903, 245902, 241289, 241288},    icon = C_Item.GetItemIconByID(241289) },
    { key = "potion_of_zealotry",         category = "combat",  itemIds = {245900, 245901, 241297, 241296},    icon = C_Item.GetItemIconByID(241297) },
    { key = "liquid_luster",              category = "combat",  itemIds = {274763, 274764, 271887, 271886},    icon = C_Item.GetItemIconByID(271887) },
    { key = "alluring_nostrum",           category = "combat",  itemIds = {274765, 271890, 271889},    icon = C_Item.GetItemIconByID(271890) },

    -- === Midnight Health Potions ===
    { key = "concentrated_silvermoon_health_potion", category = "health",  itemIds = {271884, 271883},    icon = C_Item.GetItemIconByID(271884) },
    { key = "silvermoon_health_potion",   category = "health",  itemIds = {245919, 245918, 241305, 241304},    icon = C_Item.GetItemIconByID(241305) },
    { key = "refreshing_serum",           category = "health",  itemIds = {241307, 241306},    icon = C_Item.GetItemIconByID(241307) },
    { key = "amani_extract",              category = "health",  itemIds = {241299, 241298},    icon = C_Item.GetItemIconByID(241299) },
    { key = "potent_healing_potion",      category = "health",  itemIds = {258138},            icon = C_Item.GetItemIconByID(258138) },

    -- === Midnight Mana Potions ===
    { key = "lightfused_mana_potion",     category = "mana",  itemIds = {245917, 245916, 241301, 241300},    icon = C_Item.GetItemIconByID(241301) },

    -- === Healthstones ===
    { key = "healthstone",                category = "healthstone",  itemIds = {5512},      icon = C_Item.GetItemIconByID(5512) },
    { key = "demonic_healthstone",        category = "healthstone",  itemIds = {224464},    icon = C_Item.GetItemIconByID(224464) },

    -- === Utility ===
    { key = "void_touched_drums",         category = "utility",  itemIds = {244639},            icon = C_Item.GetItemIconByID(244639) },
    { key = "emergency_soul_link",        category = "utility",  itemIds = {248486, 269586},    icon = C_Item.GetItemIconByID(248486) },
}

-- WoW Forever.  Every ID checked in that client's DB2 (build 1.60.1.70245).
-- Potions share one 120 s cooldown (SpellCategory 4).  Healthstones are plain
-- items with an item cooldown, not charge spells as on retail; they and the
-- runes share SpellCategory 1153, not the potions' one.
---@type consumable_family[]
local FOREVER_FAMILIES = {
    -- === Combat ===
    { key = "rejuvenation_potion",              category = "combat",  itemIds = {2456, 18253},    icon = C_Item.GetItemIconByID(18253) },  -- Minor, Major Rejuvenation Potion
    { key = "rage_potion",                      category = "combat",  itemIds = {5631, 5633, 13442},    icon = C_Item.GetItemIconByID(13442) },  -- Rage, Great Rage, Mighty Rage Potion
    { key = "stoneshield_potion",               category = "combat",  itemIds = {4623, 13455},    icon = C_Item.GetItemIconByID(13455) },  -- Lesser, Greater Stoneshield Potion
    { key = "free_action_potion",               category = "combat",  itemIds = {5634},    icon = C_Item.GetItemIconByID(5634) },
    { key = "living_action_potion",             category = "combat",  itemIds = {20008},    icon = C_Item.GetItemIconByID(20008) },
    { key = "limited_invulnerability_potion",   category = "combat",  itemIds = {3387},    icon = C_Item.GetItemIconByID(3387) },
    { key = "restorative_potion",               category = "combat",  itemIds = {9030},    icon = C_Item.GetItemIconByID(9030) },
    { key = "fire_protection_potion",           category = "combat",  itemIds = {6049, 13457},    icon = C_Item.GetItemIconByID(13457) },
    { key = "frost_protection_potion",          category = "combat",  itemIds = {6050, 13456},    icon = C_Item.GetItemIconByID(13456) },
    { key = "nature_protection_potion",         category = "combat",  itemIds = {6052, 13458},    icon = C_Item.GetItemIconByID(13458) },
    { key = "shadow_protection_potion",         category = "combat",  itemIds = {6048, 13459},    icon = C_Item.GetItemIconByID(13459) },
    { key = "arcane_protection_potion",         category = "combat",  itemIds = {13461},    icon = C_Item.GetItemIconByID(13461) },

    -- === Health / Mana ===
    { key = "healing_potion",                   category = "health",  itemIds = {118, 858, 929, 1710, 3928, 13446},    icon = C_Item.GetItemIconByID(13446) },  -- Minor … Major Healing Potion
    { key = "mana_potion",                      category = "mana",  itemIds = {2455, 3385, 3827, 6149, 13443, 13444},    icon = C_Item.GetItemIconByID(13444) },  -- Minor … Major Mana Potion

    -- === Healthstones: per tier base, Improved Healthstone rank 1, rank 2 ===
    { key = "healthstone",                      category = "healthstone",  itemIds = {5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013},    icon = C_Item.GetItemIconByID(19013) },

    -- === Utility ===
    -- Mana, but every caster uses them, so not behind mana's healer-only auto-hide.
    { key = "dark_rune",                        category = "utility",  itemIds = {12662, 20520},    icon = C_Item.GetItemIconByID(20520) },  -- Demonic, Dark Rune
    { key = "dreamless_sleep_potion",           category = "utility",  itemIds = {12190, 20002},    icon = C_Item.GetItemIconByID(20002) },
    { key = "purification_potion",              category = "utility",  itemIds = {13462},    icon = C_Item.GetItemIconByID(13462) },
    { key = "swiftness_potion",                 category = "utility",  itemIds = {2459},    icon = C_Item.GetItemIconByID(2459) },
    { key = "invisibility_potion",              category = "utility",  itemIds = {3823, 9172},    icon = C_Item.GetItemIconByID(9172) },  -- Lesser, Invisibility Potion
}

-- MoP Classic.  Every ID checked in that client's DB2 (build 5.5.4.70032).
-- Potions share SpellCategory 4.  The Healthstone is a plain item with three
-- uses and an item cooldown.  MoP has no drums.
---@type consumable_family[]
local MISTS_FAMILIES = {
    -- === Combat ===
    { key = "potion_of_the_jade_serpent",       category = "combat",  itemIds = {76093},    icon = C_Item.GetItemIconByID(76093) },  -- Intellect
    { key = "virmens_bite",                     category = "combat",  itemIds = {76089},    icon = C_Item.GetItemIconByID(76089) },  -- Agility
    { key = "potion_of_mogu_power",             category = "combat",  itemIds = {76095},    icon = C_Item.GetItemIconByID(76095) },  -- Strength
    { key = "potion_of_the_mountains",          category = "combat",  itemIds = {76090},    icon = C_Item.GetItemIconByID(76090) },  -- Armor

    -- === Health ===
    { key = "master_healing_potion",            category = "health",  itemIds = {76097, 80040},    icon = C_Item.GetItemIconByID(76097) },  -- Master, Endless Master Healing Potion (never used up)
    { key = "alchemists_rejuvenation",          category = "health",  itemIds = {76094},    icon = C_Item.GetItemIconByID(76094) },
    { key = "life_spirit",                      category = "health",  itemIds = {89640},    icon = C_Item.GetItemIconByID(89640) },

    -- === Mana ===
    { key = "master_mana_potion",               category = "mana",  itemIds = {76098},    icon = C_Item.GetItemIconByID(76098) },
    { key = "potion_of_focus",                  category = "mana",  itemIds = {76092},    icon = C_Item.GetItemIconByID(76092) },
    { key = "water_spirit",                     category = "mana",  itemIds = {89641},    icon = C_Item.GetItemIconByID(89641) },

    -- === Healthstone ===
    { key = "healthstone",                      category = "healthstone",  itemIds = {5512},    icon = C_Item.GetItemIconByID(5512) },

    -- === Utility ===
    { key = "darkwater_potion",                 category = "utility",  itemIds = {76096},    icon = C_Item.GetItemIconByID(76096) },  -- swim speed
}

-- TBC Classic (Anniversary).  Every ID checked in that client's DB2 (build
-- 2.5.6.69795).  Potions share SpellCategory 4, healthstones and runes 1153,
-- drums 24.  The vanilla families stay: their items still drop and sell.
---@type consumable_family[]
local TBC_FAMILIES = {
    -- === Combat ===
    { key = "haste_potion",                     category = "combat",  itemIds = {22838},    icon = C_Item.GetItemIconByID(22838) },
    { key = "destruction_potion",               category = "combat",  itemIds = {22839},    icon = C_Item.GetItemIconByID(22839) },
    { key = "heroic_potion",                    category = "combat",  itemIds = {22837},    icon = C_Item.GetItemIconByID(22837) },
    { key = "insane_strength_potion",           category = "combat",  itemIds = {22828},    icon = C_Item.GetItemIconByID(22828) },
    { key = "ironshield_potion",                category = "combat",  itemIds = {22849},    icon = C_Item.GetItemIconByID(22849) },
    { key = "rejuvenation_potion",              category = "combat",  itemIds = {2456, 18253, 22850},    icon = C_Item.GetItemIconByID(22850) },  -- Minor, Major, Super Rejuvenation Potion
    { key = "mad_alchemists_potion",            category = "combat",  itemIds = {34440},    icon = C_Item.GetItemIconByID(34440) },
    { key = "fel_regeneration_potion",          category = "combat",  itemIds = {31676},    icon = C_Item.GetItemIconByID(31676) },
    { key = "rage_potion",                      category = "combat",  itemIds = {5631, 5633, 13442},    icon = C_Item.GetItemIconByID(13442) },  -- Rage, Great Rage, Mighty Rage Potion
    { key = "stoneshield_potion",               category = "combat",  itemIds = {4623, 13455},    icon = C_Item.GetItemIconByID(13455) },  -- Lesser, Greater Stoneshield Potion
    { key = "free_action_potion",               category = "combat",  itemIds = {5634},    icon = C_Item.GetItemIconByID(5634) },
    { key = "living_action_potion",             category = "combat",  itemIds = {20008},    icon = C_Item.GetItemIconByID(20008) },
    { key = "limited_invulnerability_potion",   category = "combat",  itemIds = {3387},    icon = C_Item.GetItemIconByID(3387) },
    { key = "restorative_potion",               category = "combat",  itemIds = {9030},    icon = C_Item.GetItemIconByID(9030) },
    { key = "fire_protection_potion",           category = "combat",  itemIds = {6049, 13457, 32846, 22841},    icon = C_Item.GetItemIconByID(22841) },
    { key = "frost_protection_potion",          category = "combat",  itemIds = {6050, 13456, 32847, 22842},    icon = C_Item.GetItemIconByID(22842) },
    { key = "nature_protection_potion",         category = "combat",  itemIds = {6052, 13458, 32844, 22844},    icon = C_Item.GetItemIconByID(22844) },
    { key = "shadow_protection_potion",         category = "combat",  itemIds = {6048, 13459, 32845, 22846},    icon = C_Item.GetItemIconByID(22846) },
    { key = "arcane_protection_potion",         category = "combat",  itemIds = {13461, 32840, 22845},    icon = C_Item.GetItemIconByID(22845) },
    { key = "holy_protection_potion",           category = "combat",  itemIds = {6051, 13460, 22847},    icon = C_Item.GetItemIconByID(22847) },

    -- === Health ===
    { key = "healing_potion",                   category = "health",  itemIds = {118, 858, 929, 1710, 3928, 13446, 28100, 32947, 33934, 32904, 22829},    icon = C_Item.GetItemIconByID(22829) },  -- Minor … Major Healing Potion; Volatile, Auchenai, Crystal, Cenarion; Super Healing Potion

    -- === Mana ===
    { key = "mana_potion",                      category = "mana",  itemIds = {2455, 3385, 3827, 6149, 13443, 13444, 28101, 32948, 33935, 32903, 22832},    icon = C_Item.GetItemIconByID(22832) },  -- Minor … Major Mana Potion; Unstable, Auchenai, Crystal, Cenarion; Super Mana Potion
    { key = "fel_mana_potion",                  category = "mana",  itemIds = {31677},    icon = C_Item.GetItemIconByID(31677) },

    -- === Healthstones ===
    { key = "healthstone",                      category = "healthstone",  itemIds = {5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013, 22103, 22104, 22105},    icon = C_Item.GetItemIconByID(22105) },

    -- === Utility ===
    { key = "dark_rune",                        category = "utility",  itemIds = {12662, 20520},    icon = C_Item.GetItemIconByID(20520) },  -- Demonic, Dark Rune
    { key = "dreamless_sleep_potion",           category = "utility",  itemIds = {12190, 20002, 22836},    icon = C_Item.GetItemIconByID(22836) },  -- Dreamless, Greater, Major Dreamless Sleep Potion
    { key = "purification_potion",              category = "utility",  itemIds = {13462},    icon = C_Item.GetItemIconByID(13462) },
    { key = "swiftness_potion",                 category = "utility",  itemIds = {2459},    icon = C_Item.GetItemIconByID(2459) },
    { key = "invisibility_potion",              category = "utility",  itemIds = {3823, 9172},    icon = C_Item.GetItemIconByID(9172) },  -- Lesser, Invisibility Potion
    { key = "sneaking_potion",                  category = "utility",  itemIds = {22826},    icon = C_Item.GetItemIconByID(22826) },
    { key = "shrouding_potion",                 category = "utility",  itemIds = {22871},    icon = C_Item.GetItemIconByID(22871) },
    { key = "drums_of_battle",                  category = "utility",  itemIds = {29529, 185848},    icon = C_Item.GetItemIconByID(185848) },  -- Drums, Greater Drums
    { key = "drums_of_war",                     category = "utility",  itemIds = {29528, 185852},    icon = C_Item.GetItemIconByID(185852) },
    { key = "drums_of_restoration",             category = "utility",  itemIds = {29531, 185850},    icon = C_Item.GetItemIconByID(185850) },
    { key = "drums_of_speed",                   category = "utility",  itemIds = {29530, 185851},    icon = C_Item.GetItemIconByID(185851) },
    { key = "drums_of_panic",                   category = "utility",  itemIds = {29532, 185849},    icon = C_Item.GetItemIconByID(185849) },
}

-- Wrath Classic (Titan).  Every ID checked in that client's DB2 (build
-- 3.80.2.70177); Titan renames a few older potions (Potion of Rituals is the
-- Greater Dreamless Sleep Potion).  Same categories as TBC.
---@type consumable_family[]
local WRATH_FAMILIES = {
    -- === Combat ===
    { key = "potion_of_speed",                  category = "combat",  itemIds = {40211},    icon = C_Item.GetItemIconByID(40211) },
    { key = "potion_of_wild_magic",             category = "combat",  itemIds = {40212},    icon = C_Item.GetItemIconByID(40212) },
    { key = "indestructible_potion",            category = "combat",  itemIds = {40093},    icon = C_Item.GetItemIconByID(40093) },
    { key = "crazy_alchemists_potion",          category = "combat",  itemIds = {40077},    icon = C_Item.GetItemIconByID(40077) },
    { key = "haste_potion",                     category = "combat",  itemIds = {22838},    icon = C_Item.GetItemIconByID(22838) },
    { key = "destruction_potion",               category = "combat",  itemIds = {22839},    icon = C_Item.GetItemIconByID(22839) },
    { key = "heroic_potion",                    category = "combat",  itemIds = {22837},    icon = C_Item.GetItemIconByID(22837) },
    { key = "insane_strength_potion",           category = "combat",  itemIds = {22828},    icon = C_Item.GetItemIconByID(22828) },
    { key = "ironshield_potion",                category = "combat",  itemIds = {22849},    icon = C_Item.GetItemIconByID(22849) },
    { key = "rejuvenation_potion",              category = "combat",  itemIds = {2456, 18253, 22850, 40087},    icon = C_Item.GetItemIconByID(40087) },  -- Minor, Major, Super, Powerful Rejuvenation Potion
    { key = "rage_potion",                      category = "combat",  itemIds = {5631, 5633, 13442},    icon = C_Item.GetItemIconByID(13442) },  -- Rage, Great Rage, Mighty Rage Potion
    { key = "stoneshield_potion",               category = "combat",  itemIds = {4623, 13455},    icon = C_Item.GetItemIconByID(13455) },  -- Lesser, Greater Stoneshield Potion
    { key = "free_action_potion",               category = "combat",  itemIds = {5634},    icon = C_Item.GetItemIconByID(5634) },
    { key = "living_action_potion",             category = "combat",  itemIds = {20008},    icon = C_Item.GetItemIconByID(20008) },
    { key = "limited_invulnerability_potion",   category = "combat",  itemIds = {3387},    icon = C_Item.GetItemIconByID(3387) },
    { key = "fire_protection_potion",           category = "combat",  itemIds = {6049, 13457, 32846, 22841, 40214},    icon = C_Item.GetItemIconByID(40214) },
    { key = "frost_protection_potion",          category = "combat",  itemIds = {6050, 13456, 32847, 22842, 40215},    icon = C_Item.GetItemIconByID(40215) },
    { key = "nature_protection_potion",         category = "combat",  itemIds = {6052, 13458, 32844, 22844, 40216},    icon = C_Item.GetItemIconByID(40216) },
    { key = "shadow_protection_potion",         category = "combat",  itemIds = {6048, 13459, 32845, 22846, 40217},    icon = C_Item.GetItemIconByID(40217) },
    { key = "arcane_protection_potion",         category = "combat",  itemIds = {13461, 32840, 22845, 40213},    icon = C_Item.GetItemIconByID(40213) },
    { key = "holy_protection_potion",           category = "combat",  itemIds = {6051, 13460, 22847},    icon = C_Item.GetItemIconByID(22847) },

    -- === Health ===
    { key = "healing_potion",                   category = "health",  itemIds = {118, 858, 929, 1710, 3928, 13446, 22829, 43569, 39671, 41166, 33447},    icon = C_Item.GetItemIconByID(33447) },  -- Minor … Super Healing Potion; Endless (never used up), Resurgent; Runic Healing Injector, Potion

    -- === Mana ===
    { key = "mana_potion",                      category = "mana",  itemIds = {2455, 3385, 3827, 6149, 13443, 13444, 22832, 43570, 40067, 42545, 33448},    icon = C_Item.GetItemIconByID(33448) },  -- Minor … Super Mana Potion; Endless (never used up), Icy; Runic Mana Injector, Potion
    { key = "fel_mana_potion",                  category = "mana",  itemIds = {31677},    icon = C_Item.GetItemIconByID(31677) },

    -- === Healthstones ===
    { key = "healthstone",                      category = "healthstone",  itemIds = {5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013, 22103, 22104, 22105, 36889, 36890, 36891, 36892, 36893, 36894},    icon = C_Item.GetItemIconByID(36894) },

    -- === Utility ===
    { key = "dark_rune",                        category = "utility",  itemIds = {12662, 20520},    icon = C_Item.GetItemIconByID(20520) },  -- Demonic, Dark Rune
    { key = "dreamless_sleep_potion",           category = "utility",  itemIds = {12190, 20002, 22836, 40081},    icon = C_Item.GetItemIconByID(40081) },  -- Dreamless … Major Dreamless Sleep Potion, Potion of Nightmares
    { key = "purification_potion",              category = "utility",  itemIds = {13462},    icon = C_Item.GetItemIconByID(13462) },
    { key = "swiftness_potion",                 category = "utility",  itemIds = {2459},    icon = C_Item.GetItemIconByID(2459) },
    { key = "invisibility_potion",              category = "utility",  itemIds = {3823, 9172},    icon = C_Item.GetItemIconByID(9172) },  -- Lesser, Invisibility Potion
    { key = "sneaking_potion",                  category = "utility",  itemIds = {22826},    icon = C_Item.GetItemIconByID(22826) },
    { key = "shrouding_potion",                 category = "utility",  itemIds = {22871},    icon = C_Item.GetItemIconByID(22871) },
    { key = "drums_of_forgotten_kings",         category = "utility",  itemIds = {49633},    icon = C_Item.GetItemIconByID(49633) },
    { key = "drums_of_the_wild",                category = "utility",  itemIds = {49634},    icon = C_Item.GetItemIconByID(49634) },
    { key = "drums_of_battle",                  category = "utility",  itemIds = {29529, 185848},    icon = C_Item.GetItemIconByID(185848) },  -- Drums, Greater Drums
    { key = "drums_of_war",                     category = "utility",  itemIds = {29528, 185852},    icon = C_Item.GetItemIconByID(185852) },
    { key = "drums_of_restoration",             category = "utility",  itemIds = {29531, 185850},    icon = C_Item.GetItemIconByID(185850) },
    { key = "drums_of_speed",                   category = "utility",  itemIds = {29530, 185851},    icon = C_Item.GetItemIconByID(185851) },
    { key = "drums_of_panic",                   category = "utility",  itemIds = {29532, 185849},    icon = C_Item.GetItemIconByID(185849) },
}

-- Classic Era carries Forever's vanilla items under the same IDs and
-- categories (DB2 1.15.9.70003), so it shares the list.
local CONSUMABLE_FAMILIES = ({
    retail = RETAIL_FAMILIES, forever = FOREVER_FAMILIES, era = FOREVER_FAMILIES,
    tbc = TBC_FAMILIES, wrath = WRATH_FAMILIES, mists = MISTS_FAMILIES,
})[private.ClientScope.CLIENT] or {}


---Ordered category keys for grouping in the Edit Mode UI and Options panel.
---@type string[]
local CATEGORY_ORDER = { "combat", "health", "mana", "healthstone", "utility" }

---Category key → locale string key.
---@type table<string, string>
local CATEGORY_LABELS = {
    combat = "CONSUMABLE_CAT_COMBAT",
    health = "CONSUMABLE_CAT_HEALTH",
    mana = "CONSUMABLE_CAT_MANA",
    healthstone = "CONSUMABLE_CAT_HEALTHSTONE",
    utility = "CONSUMABLE_CAT_UTILITY",
}

---@class category_config
---@field best_only boolean  when true, only show one icon (the best item) for this category
---@field auto_hide_non_healer boolean?  when true, hide this category for non-healer specs

---Per-category runtime behaviour.
---@type table<string, category_config>
local CATEGORY_CONFIG = {
    combat = { best_only = false },
    health = { best_only = true },
    mana = { best_only = true, auto_hide_non_healer = true },
    healthstone = { best_only = false },
    utility = { best_only = false },
}

-- Build a familyKey → category lookup for identifying health-related icons.
---@type table<string, string>
local FAMILY_CATEGORY = {}
for _, family in ipairs(CONSUMABLE_FAMILIES) do
    FAMILY_CATEGORY[family.key] = family.category
end

-- ---------------------------------------------------------------------------
-- Low health curve
-- ---------------------------------------------------------------------------
-- A step curve that maps player health percentage [0, 1] to an alpha value:
-- below threshold → 1.0 (border visible), at/above threshold → 0.0 (hidden).
-- Passed to UnitHealthPercent("player", true, curve) which returns a secret
-- alpha value suitable for Frame:SetAlpha(). Rebuilt when the threshold changes.
--
-- Evidence:
--   C_CurveUtil.CreateCurve — CurveUtilDocumentation.lua
--   Enum.LuaCurveType.Step — CurveConstants.lua (Blizzard_SharedXMLBase)
--   UnitHealthPercent(unit, usePredicted, curve) — UnitDocumentation.lua:1384-1403
--   Frame:SetAlpha accepts secret values — SimpleFrameAPIDocumentation.lua:1028-1036
--     (SecretArguments = "AllowedWhenTainted")

---@type table?  CurveObject for low health alpha evaluation
local lowHealthCurve
---@type number?  cached threshold that built the current curve
local lowHealthCurveThreshold

---Build or rebuild the step curve when the threshold changes.
---@param thresholdPct number  health threshold as a percentage (e.g. 35)
---@return table curve  CurveObject to pass to UnitHealthPercent
local function getLowHealthCurve(thresholdPct)
    if lowHealthCurve and lowHealthCurveThreshold == thresholdPct then
        return lowHealthCurve
    end
    lowHealthCurve = C_CurveUtil.CreateCurve()
    lowHealthCurve:SetType(Enum.LuaCurveType.Step)
    lowHealthCurve:AddPoint(0.0, 1.0)
    lowHealthCurve:AddPoint(thresholdPct / 100, 0.0)
    lowHealthCurveThreshold = thresholdPct
    return lowHealthCurve
end

-- GCD threshold: cooldowns shorter than this are treated as GCD and ignored
local GCD_THRESHOLD = 1.5

---Returns true while the player is inside an active Mythic+ keystone run.
---Used to gate the persistent "ready in M+" pulse glow.
local function isInActiveMythicPlus()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive() or false
end

-- ---------------------------------------------------------------------------
-- Cooldown helper for charged items
-- ---------------------------------------------------------------------------
-- C_Item.GetItemCooldown does not report per-charge recharge cooldowns for
-- items like Demonic Healthstone (single item with 3 charges). The action bar
-- uses C_Container.GetContainerItemCooldown which does report them.  This
-- helper tries the item-level API first and falls back to a cached bag/slot
-- lookup (rebuilt on BAG_UPDATE_DELAYED) to avoid per-tick bag scanning.
--
-- Items modeled as charge spells (e.g. classic Healthstone, item 5512 → spell
-- 6262, 3 charges). C_Item.GetItemCooldown and the bag/slot fallback both
-- return 0 for these. Out of combat, the spell begins recharging immediately
-- after use and the charge API reports it; in combat the spell does NOT enter
-- recharge until combat ends, so the branch silently returns nothing then.

---Retail only: on a classic-content client 5512 is a plain item with an item
---cooldown, and spell 6262 carries no charges (DB2 1.60.1.70245, 5.5.4.70032).
---@type table<number, number>  itemId -> charge spellId
local ITEM_COOLDOWN_SPELL = private.ClientScope.CLIENT ~= "retail" and {} or {
    [5512]   = 6262,
    [224464] = 6262,  -- Demonic Healthstone — defaulted to 6262, pending verification
}

---Cached bag/slot locations keyed by itemId. Rebuilt by rebuildSlotCache().
---@type table<number, {bag: number, slot: number}>
local itemSlotCache = {}
local slotCacheDirty = true

---Scan all bags and cache the first bag/slot for each itemId.
---Called on BAG_UPDATE_DELAYED and during Enable. Skipped when cache is clean.
local function rebuildSlotCache()
    if not slotCacheDirty then return end
    slotCacheDirty = false
    wipe(itemSlotCache)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not itemSlotCache[info.itemID] then
                itemSlotCache[info.itemID] = { bag = bag, slot = slot }
            end
        end
    end
end

---@param itemId number
---@return number start, number duration, number|boolean enabled, any? spellDurationObject, boolean? unusable
local function getItemCooldown(itemId)
    local start, duration, enabled = private.compat.GetItemCooldown(itemId)
    -- Used, but the cooldown waits for an event: MoP Classic's potions
    -- (SpellCategory 4 carries flag 4, COOLDOWN_STARTS_ON_EVENT, DB2
    -- 5.5.4.70032; TBC's does not) start theirs when combat ends, and until
    -- then the read says not enabled.  Shown as used, with no sweep yet.
    if start and enabled == false then
        return 0, 0, 0, nil, true
    end
    if start and start > 0 and duration and duration > GCD_THRESHOLD then
        return start, duration, enabled
    end
    -- Fallback: use cached bag/slot to check container cooldown (no bag scan)
    local cached = itemSlotCache[itemId]
    if cached then
        local cStart, cDuration, cEnabled = C_Container.GetContainerItemCooldown(cached.bag, cached.slot)
        if cStart and cStart > 0 and cDuration and cDuration > GCD_THRESHOLD then
            return cStart, cDuration, cEnabled
        end
    end
    -- Items modeled as charge spells (Healthstone variants). chargeInfo.isActive
    -- is NeverSecret and reports "recharging"; combine with GetSpellChargeDuration's
    -- DurationObject for SetCooldownFromDurationObject. In-combat the spell does
    -- not enter recharge — C_Spell.IsSpellUsable returns false while the use is
    -- locked out, which we surface as desaturated-but-no-sweep.
    local spellId = ITEM_COOLDOWN_SPELL[itemId]
    if spellId then
        local chargeInfo = C_Spell.GetSpellCharges(spellId)
        if chargeInfo and chargeInfo.isActive then
            local durObj = C_Spell.GetSpellChargeDuration(spellId)
            if durObj then
                return 0, 0, 1, durObj
            end
        end
        if C_Spell.IsSpellUsable(spellId) == false then
            return 0, 0, 0, nil, true
        end
    end
    return start or 0, duration or 0, enabled or 0
end

-- Every sweep writer goes through this: the layout path below runs on every
-- layout pass, and a re-issued sweep restarts the engine countdown.
local applyIconCooldown = private.Util.SetIconCooldown

-- Throttle OnUpdate to ~5 fps for cooldown sweep updates
local UPDATE_INTERVAL = 0.2
local timeSinceLastUpdate = 0

---@type frame?  container frame
local consumableContainer

---@type table<string, frame>  familyKey -> icon frame (stable, one per family)
local consumableIcons = {}

---@type frame[]  ordered list of active icons for layout/iteration
local orderedIcons = {}

---@type frame?  event listener frame
local eventFrame
---@type boolean
local keybindEventsRegistered = false

---@type number  cached count of currently active (visible) families
local activeCount = 0

-- Stable numeric IDs for consumable categories, used as routing keys.
-- Entries in assigned_spells are stored as {categoryID, "Consumable"}.
---@type table<string, number>
local CONSUMABLE_CATEGORY_IDS = {
    combat = 1,
    health = 2,
    mana = 3,
    healthstone = 4,
    utility = 5,
}
---@type table<number, string>
local CONSUMABLE_ID_TO_CATEGORY = {}
for cat, id in pairs(CONSUMABLE_CATEGORY_IDS) do
    CONSUMABLE_ID_TO_CATEGORY[id] = cat
end

-- ---------------------------------------------------------------------------
-- Public accessors for EditMode UI and Options panel
-- ---------------------------------------------------------------------------

---Return the family registry so Options can build per-family checkboxes.
---@return consumable_family[]
consumableTracker.GetFamilies = function()
    return CONSUMABLE_FAMILIES
end

---Return the ordered category keys for grouped display.
---@return string[]
consumableTracker.GetCategoryOrder = function()
    return CATEGORY_ORDER
end

---Return the locale key for a category.
---@param category string
---@return string
consumableTracker.GetCategoryLabel = function(category)
    return CATEGORY_LABELS[category] or category
end

---Return the localized display name for a family, fetched from item info.
---Uses the highest-rank item ID; falls back to the family key if not yet cached.
---@param family consumable_family
---@return string
consumableTracker.GetFamilyName = function(family)
    return C_Item.GetItemNameByID(family.itemIds[#family.itemIds]) or family.key
end

-- ---------------------------------------------------------------------------
-- Settings helpers
-- ---------------------------------------------------------------------------

---@return consumable_tracker_profile_main
local function getSettings()
    return private.profile.components[consumableTracker.name]
end

consumableTracker.GetSettings = getSettings

local getEnabled = function()
    local settings = getSettings()
    return settings.enabled
end

consumableTracker.GetEnabled = getEnabled

-- ---------------------------------------------------------------------------
-- Auto-hide helper
-- ---------------------------------------------------------------------------

---Returns true when the mana category should be hidden for the current spec.
---@return boolean
local function shouldHideManaForSpec()
    if not private.profile.consumable_auto_hide then return false end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        local role = private.compat.GetSpecializationRole(specIndex)
        if role and role ~= "HEALER" then
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Family resolution
-- ---------------------------------------------------------------------------

---@class active_family_entry
---@field familyKey string
---@field itemId number   the best (highest rank) item ID the player has
---@field count number    total count across all ranks in the family
---@field icon number?    fileID from C_Item.GetItemIconByID

---Build a lookup table grouping families by category.
---@return table<string, consumable_family[]>
local function buildFamiliesByCategory()
    local familiesByCategory = {}
    for _, family in ipairs(CONSUMABLE_FAMILIES) do
        if not familiesByCategory[family.category] then
            familiesByCategory[family.category] = {}
        end
        local catList = familiesByCategory[family.category]
        catList[#catList + 1] = family
    end
    return familiesByCategory
end

---Scan bags for tracked families, respecting category toggles and best_only logic.
---Returns an ordered list of entries for families the player actually has,
---or placeholder entries when in Edit Mode. Categories disabled via
---tracked_categories are skipped entirely. For best_only categories (health,
---mana), only the first (highest-priority) family with items is returned.
---Mana is auto-hidden for non-healer specs when auto_hide is on (except in
---Edit Mode).
---@return active_family_entry[]
local function getActiveFamilies()
    local settings = getSettings()
    local tracked = settings.tracked_families
    local trackedCategories = settings.tracked_categories
    local result = {}

    local familiesByCategory = buildFamiliesByCategory()

    for _, category in ipairs(CATEGORY_ORDER) do
        -- Skip disabled categories (default to enabled if absent)
        local categoryEnabled = trackedCategories[category]
        if categoryEnabled == nil then categoryEnabled = true end

        -- Auto-hide mana for non-healer specs (except in Edit Mode)
        local config = CATEGORY_CONFIG[category]
        if config.auto_hide_non_healer and not private.isEditMode and shouldHideManaForSpec() then
            categoryEnabled = false
        end

        if categoryEnabled then
            local catFamilies = familiesByCategory[category] or {}

            for _, family in ipairs(catFamilies) do
                -- Default to tracked if the key is absent from the profile
                local isTracked = tracked[family.key]
                if isTracked == nil then
                    isTracked = true
                end
                if isTracked then
                    local bestItemId = nil
                    local totalCount = 0

                    -- Iterate ranks in reverse (highest rank last in the array → check last first)
                    for i = #family.itemIds, 1, -1 do
                        local itemId = family.itemIds[i]
                        local count = C_Item.GetItemCount(itemId, false, true)
                        totalCount = totalCount + count
                        if count > 0 and not bestItemId then
                            bestItemId = itemId
                        end
                    end

                    -- In Edit Mode, show one icon per category (best representative)
                    -- regardless of best_only config, so the preview stays compact.
                    local breakAfter = config.best_only or private.isEditMode

                    if totalCount > 0 then
                        result[#result + 1] = {
                            familyKey = family.key,
                            itemId = bestItemId,
                            count = totalCount,
                            icon = bestItemId and C_Item.GetItemIconByID(bestItemId) or nil,
                        }
                        if breakAfter then
                            break
                        end
                    elseif private.isEditMode then
                        -- Show placeholder in Edit Mode even if player has none
                        local placeholderItem = family.itemIds[#family.itemIds]
                        result[#result + 1] = {
                            familyKey = family.key,
                            itemId = placeholderItem,
                            count = 0,
                            icon = C_Item.GetItemIconByID(placeholderItem),
                        }
                        -- Always break in Edit Mode: one representative per category
                        break
                    end
                end
            end
        end
    end

    return result
end

---Check whether a consumable icon is routed away from ConsumableTracker's own layout.
---An icon is routed if its category is assigned to an AdditionalFrame OR the icon is
---displayed in CooldownTracker's grid (combat potions only).
---@param icon frame
---@return boolean
local function isIconRouted(icon)
    local catID = icon.category and CONSUMABLE_CATEGORY_IDS[icon.category]
    if catID then
        local afm = private.AdditionalFrameManager
        if afm and afm.IsSpellRouted(catID, "Consumable") then return true end
    end
    local ct = private.CooldownTracker
    if ct and ct.IsIconRoutedHere and ct.IsIconRoutedHere(icon) then return true end
    return false
end

---Returns the visual settings to use for a consumable icon.
---When routed to CooldownTracker, returns CT's settings so visual properties
---(desaturation, cd text) match the host component.
---@param icon frame
---@return table
local function getVisualSettings(icon)
    local ct = private.CooldownTracker
    if ct and ct.IsIconRoutedHere and ct.IsIconRoutedHere(icon) then
        return ct.GetSettings()
    end
    return getSettings()
end

---Count how many active icons are routed away from ConsumableTracker.
---@return number
local function getRoutedIconCount()
    local count = 0
    for _, icon in ipairs(orderedIcons) do
        if isIconRouted(icon) then
            count = count + 1
        end
    end
    return count
end

---Returns the number of icons the container should reserve space for.
---In Edit Mode: accounts for best_only (1 per best_only category, N per normal).
---At runtime: count of active families from the last refresh, minus routed.
---@return number
local function getEffectiveIconLimit()
    if private.isEditMode then
        -- Edit Mode shows one icon per enabled category (best representative),
        -- matching the compact preview from getActiveFamilies().
        local settings = getSettings()
        local tracked = settings.tracked_families
        local trackedCategories = settings.tracked_categories
        local count = 0

        local familiesByCategory = buildFamiliesByCategory()

        for _, category in ipairs(CATEGORY_ORDER) do
            local categoryEnabled = trackedCategories[category]
            if categoryEnabled == nil then categoryEnabled = true end

            if categoryEnabled then
                local catFamilies = familiesByCategory[category] or {}
                for _, family in ipairs(catFamilies) do
                    local isTracked = tracked[family.key]
                    if isTracked == nil then isTracked = true end
                    if isTracked then
                        count = count + 1
                        break -- one icon per category in Edit Mode
                    end
                end
            end
        end

        return math.max(count, 1)
    end
    return math.max(activeCount - getRoutedIconCount(), 0)
end

-- ---------------------------------------------------------------------------
-- Icon frame creation
-- ---------------------------------------------------------------------------


---Create a single consumable icon frame as a child of the container.
---@param container frame
---@return frame
local function createConsumableIcon(container)
    local icon = CreateFrame("Button", nil, container)
    icon:EnableMouse(false)

    -- Install CUE tooltip on this addon-owned icon. Resolver reads icon.itemId
    -- (assigned in Refresh as each pooled icon takes on a family).
    if private.Tooltip then
        private.Tooltip.Apply(icon, getSettings, function(self)
            if not self.itemId then return nil, nil end
            return "item", self.itemId
        end, { kind = "own", isSecureClick = false })
    end

    -- Icon texture (fills the button)
    icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
    icon.Icon:SetSnapToPixelGrid(false)
    icon.Icon:SetTexelSnappingBias(0)
    icon.Icon:SetAllPoints()
    icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords())

    -- Cooldown sweep overlay
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetFrameLevel(icon:GetFrameLevel() + 1)
    cd:SetDrawEdge(false)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetSwipeColor(0, 0, 0, 0.7)
    cd:SetHideCountdownNumbers(false)
    cd:SetCountdownAbbrevThreshold(120)
    icon.Cooldown = cd

    -- Overlay frame above cooldown swipe for all text elements
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(cd)
    textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)

    -- Item count overlay (positioned and styled by count_font profile in Refresh)
    icon.Count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")

    -- Duration text: the Cooldown frame's built-in countdown FontString
    icon.DurationText = icon.Cooldown:GetRegions()
    if icon.DurationText then
        icon.DurationText:SetParent(textOverlay)
    end

    -- Keybind text overlay (positioned and styled by keybind_font profile in Refresh)
    icon.KeybindText = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.KeybindText:Hide()

    icon:Hide()
    return icon
end

local parseItemBuffDuration = private.Util.ParseItemBuffDuration

-- ---------------------------------------------------------------------------
-- Refresh logic
-- ---------------------------------------------------------------------------

---Refresh all consumable icons: resolve active families, assign to icon slots,
---update textures, cooldowns, and count overlays.
local function refreshAllIcons()
    local activeFamilies = getActiveFamilies()
    local settings = getSettings()
    activeCount = #activeFamilies

    -- Track which families are active this refresh
    local activeSet = {}
    wipe(orderedIcons)

    for _, entry in ipairs(activeFamilies) do
        local familyKey = entry.familyKey
        activeSet[familyKey] = true

        local icon = consumableIcons[familyKey]
        if not icon then
            icon = createConsumableIcon(consumableContainer)
            consumableIcons[familyKey] = icon
            -- Apply font profiles on create so the first Show() renders at
            -- the configured anchor. Without this, icon.Count / KeybindText
            -- are anchorless and render at the parent's origin until the
            -- next fontsDirty-gated refresh (e.g. /reload).
            if settings.count_font then
                private.Util.ApplyFontProfile(icon.Count, settings.count_font, icon)
            end
            if settings.duration_font and icon.DurationText then
                private.Util.ApplyFontProfile(icon.DurationText, settings.duration_font, icon)
            end
            if settings.keybind_font and icon.KeybindText then
                private.Util.ApplyFontProfile(icon.KeybindText, settings.keybind_font, icon)
            end
        end

        -- Reset glow state when icon is reassigned to a different family
        if icon.familyKey ~= familyKey then
            private.GlowEffect.StopAll(icon)
            icon.wasOnCooldown = nil
            icon.activeBuffExpiry = nil
        end

        icon.familyKey = familyKey
        icon.category = FAMILY_CATEGORY[familyKey]
        icon.itemId = entry.itemId
        icon.Icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(icon:GetSize()))

        -- Cache the item's buff duration for active glow tracking (combat potions only)
        if icon.category == "combat" then
            icon.activeBuffDuration = parseItemBuffDuration(entry.itemId)
        else
            icon.activeBuffDuration = nil
        end

        -- Cooldown sweep
        local start, duration, cdEnabled, cdDurObj, cdUnusable = getItemCooldown(entry.itemId)
        local hasRealCd = start and start > 0 and duration and duration > GCD_THRESHOLD and cdEnabled and cdEnabled ~= 0
        applyIconCooldown(icon, hasRealCd and start or nil, duration, cdDurObj)
        local isOnCooldown = cdDurObj ~= nil or cdUnusable or hasRealCd
        icon.Icon:SetDesaturated(isOnCooldown and not getVisualSettings(icon).no_desaturation)
        icon.Cooldown:SetHideCountdownNumbers(settings.hide_cd_text == true)

        -- Count overlay
        if settings.show_count and entry.count > 1 then
            icon.Count:SetText(entry.count)
            icon.Count:Show()
        else
            icon.Count:Hide()
        end

        -- Update keybind text
        local keybindFont = settings.keybind_font
        if keybindFont and keybindFont.enabled and icon.KeybindText then
            local keybindText = private.Util.GetKeybindTextForItem(entry.itemId)
            if keybindText then
                icon.KeybindText:SetText(keybindText)
                icon.KeybindText:Show()
            else
                icon.KeybindText:Hide()
            end
        elseif icon.KeybindText then
            icon.KeybindText:Hide()
        end

        icon:Show()
        orderedIcons[#orderedIcons + 1] = icon
    end

    -- Hide icons for families no longer active
    for familyKey, icon in pairs(consumableIcons) do
        if not activeSet[familyKey] then
            private.GlowEffect.StopAll(icon)
            icon.wasOnCooldown = nil
            icon.activeBuffExpiry = nil
            icon.activeBuffDuration = nil
            icon.DurationText:Hide()
            if icon.KeybindText then icon.KeybindText:Hide() end
            icon:Hide()
            icon.familyKey = nil
            icon.category = nil
            icon.itemId = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

---Compute block layout grid dimensions from the anchor side and icon count.
---Compute block grid dimensions and fill direction from explicit block_direction.
---Mirror flags derive from anchor_side so the grid starts at the appropriate corner.
---@param blockDirection string  "horizontal" (2 cols, fill left-to-right) or "vertical" (2 rows, fill top-to-bottom)
---@param anchorSide string  "top"|"bottom"|"left"|"right"|"topleft"|"topright"|"bottomleft"|"bottomright"
---@param anchorParent string  component name or "none"
---@param iconLimit number
---@return number cols
---@return number rows
---@return boolean fillVertical  true = fill columns top-to-bottom first
---@return boolean mirrorX  true = first column on the right
---@return boolean mirrorY  true = first row on the bottom
local function getBlockGridParams(blockDirection, anchorSide, anchorParent, iconLimit)
    local fillVertical = (blockDirection == "vertical")

    local cols, rows
    if fillVertical then
        rows = math.min(iconLimit, 2)
        cols = math.ceil(iconLimit / math.max(rows, 1))
    else
        cols = math.min(iconLimit, 2)
        rows = math.ceil(iconLimit / math.max(cols, 1))
    end

    local isFreeMoving = (anchorParent == "none")
    local mirrorX, mirrorY
    if isFreeMoving then
        mirrorX, mirrorY = false, false
    else
        -- Determine which sides the anchor occupies
        local anchorOnLeft = (anchorSide == "left" or anchorSide == "topleft" or anchorSide == "bottomleft")
        local anchorOnRight = (anchorSide == "right" or anchorSide == "topright" or anchorSide == "bottomright")
        local anchorOnTop = (anchorSide == "top" or anchorSide == "topleft" or anchorSide == "topright")
        local anchorOnBottom = (anchorSide == "bottom" or anchorSide == "bottomleft" or anchorSide == "bottomright")

        if fillVertical then
            -- Primary axis: columns (X) fill from outside toward anchor side.
            -- Secondary axis: rows (Y) start from anchor's Y-side.
            mirrorX = anchorOnLeft
            mirrorY = anchorOnBottom
        else
            -- Primary axis: rows (Y) fill from outside toward anchor side.
            -- Secondary axis: columns (X) start from anchor's X-side.
            mirrorY = anchorOnTop
            mirrorX = anchorOnRight
        end
    end
    return cols, rows, fillVertical, mirrorX, mirrorY
end

---Map layout_alignment to the frame_point the anchoring system should use
---so the alignment edge stays fixed when the container resizes.  Only
---applies in free-moving mode (anchor_parent == "none"); anchored mode
---derives growth from the parent relationship.  Adjusts xoff/yoff once
---so the frame doesn't jump when the point changes.  A Frame Point the user
---picked by hand (`frame_point_manual`) wins; an Edit Mode drag clears it.
local function syncFramePointToAlignment()
    if not consumableContainer then return end
    local settings = getSettings()
    local ap = settings.anchor_profile
    if not ap or ap.anchor_parent ~= "none" or ap.frame_point_manual then return end

    local layoutMode = settings.layout
    if layoutMode == "block" then return end

    local alignment = settings.layout_alignment or "left"

    -- Desired frame_point based on alignment
    local desiredFP
    if layoutMode == "horizontal" or layoutMode == nil then
        if alignment == "left" then desiredFP = "left"
        elseif alignment == "right" then desiredFP = "right"
        else desiredFP = "center" end
    elseif layoutMode == "vertical" then
        if alignment == "top" then desiredFP = "top"
        elseif alignment == "bottom" then desiredFP = "bottom"
        else desiredFP = "center" end
    end
    if not desiredFP then return end

    local currentFP = ap.frame_point
    if currentFP == desiredFP then return end

    -- Compute offset adjustment to keep the frame at the same screen
    -- position when changing frame_point.  We need the current frame
    -- bounds to calculate the shift.
    local left = consumableContainer:GetLeft()
    local right = consumableContainer:GetRight()
    local top = consumableContainer:GetTop()
    local bottom = consumableContainer:GetBottom()
    if not (left and right and top and bottom) then
        -- No valid layout yet — just set the point; first Anchor.Refresh
        -- will position correctly once the frame is shown.
        ap.frame_point = desiredFP
        return
    end

    -- Screen positions of the old and new anchor points on the frame
    local cx, cy = (left + right) / 2, (top + bottom) / 2
    local oldX, oldY = cx, cy  -- "center" default
    if currentFP == "left" then oldX = left
    elseif currentFP == "right" then oldX = right
    elseif currentFP == "top" then oldY = top
    elseif currentFP == "bottom" then oldY = bottom
    elseif currentFP == "topleft" then oldX, oldY = left, top
    elseif currentFP == "topright" then oldX, oldY = right, top
    elseif currentFP == "bottomleft" then oldX, oldY = left, bottom
    elseif currentFP == "bottomright" then oldX, oldY = right, bottom
    end

    local newX, newY = cx, cy
    if desiredFP == "left" then newX = left
    elseif desiredFP == "right" then newX = right
    elseif desiredFP == "top" then newY = top
    elseif desiredFP == "bottom" then newY = bottom
    end

    -- Shift is the screen-space difference between old and new anchor
    -- points.  Subtract from the profile offsets so the frame stays put.
    local dx = newX - oldX
    local dy = newY - oldY
    ap.xoff = (ap.xoff or 0) + dx
    ap.yoff = (ap.yoff or 0) + dy
    ap.frame_point = desiredFP
end

---Re-applies the icon layout using the profile's layout direction.
---Container size is based on iconLimit (tracked/active family count) so the frame
---occupies a stable footprint. Visible icons are positioned sequentially;
---hidden icons are sized but not anchored.
local function applyLayout()
    if not consumableContainer then return end
    -- No combat guard: container and icons are unprotected frames. Anchoring.lua
    -- writes SetHeight(parentH) in percent-match mode; applyLayout must run in
    -- combat to restore the content-driven height, else the center-pivoted
    -- anchor drifts icons up by (parentH - contentH) / 2.

    local iconLimit = getEffectiveIconLimit()

    if iconLimit <= 0 then
        consumableContainer:SetSize(1, 1)
        local bgS = getSettings().background
        if bgS then private.Util.ApplyComponentBackground(consumableContainer, bgS) end
        return
    end

    local settings = getSettings()
    local iconSize = settings.icon_size
    local iconOffset = settings.icon_offset
    local layoutMode = settings.layout

    -- Resolve icon height override (0 or nil = square).
    local hasIconHeight = settings.icon_height and settings.icon_height > 0
    local iconHeight = hasIconHeight and math.floor(settings.icon_height) or iconSize

    -- Compute container size from iconLimit
    local containerWidth, containerHeight
    -- Block-layout grid params (only used when layoutMode == "block")
    local cols, rows, fillVertical, mirrorX, mirrorY

    if layoutMode == "vertical" then
        containerWidth = iconSize
        containerHeight = iconLimit * iconHeight + (iconLimit - 1) * iconOffset
    elseif layoutMode == "block" then
        local ap = settings.anchor_profile
        cols, rows, fillVertical, mirrorX, mirrorY = getBlockGridParams(
            settings.block_direction or "horizontal", ap.anchor_side, ap.anchor_parent, iconLimit)
        containerWidth = cols * iconSize + math.max(cols - 1, 0) * iconOffset
        containerHeight = rows * iconHeight + math.max(rows - 1, 0) * iconOffset
    else
        containerWidth = iconLimit * iconSize + (iconLimit - 1) * iconOffset
        containerHeight = iconHeight
    end

    syncFramePointToAlignment()
    consumableContainer:SetSize(containerWidth, containerHeight)

    -- Position visible icons sequentially (skip routed icons — they are
    -- positioned by AdditionalFrameManager or CooldownTracker).
    local xStep = iconSize + iconOffset
    local yStep = iconHeight + iconOffset

    -- Pre-count visible non-routed icons for alignment offset calculation.
    local visibleCount = 0
    for _, icon in ipairs(orderedIcons) do
        if not isIconRouted(icon) and icon:IsShown() then
            visibleCount = visibleCount + 1
        end
    end

    -- Compute alignment offset for horizontal/vertical modes.
    local alignment = settings.layout_alignment or "left"
    local alignOffsetX, alignOffsetY = 0, 0

    if layoutMode == "horizontal" then
        local usedWidth = visibleCount > 0 and (visibleCount * xStep - iconOffset) or 0
        if alignment == "center" then
            alignOffsetX = (containerWidth - usedWidth) / 2
        elseif alignment == "right" then
            alignOffsetX = containerWidth - usedWidth
        end
    elseif layoutMode == "vertical" then
        local usedHeight = visibleCount > 0 and (visibleCount * yStep - iconOffset) or 0
        if alignment == "center" then
            alignOffsetY = (containerHeight - usedHeight) / 2
        elseif alignment == "bottom" then
            alignOffsetY = containerHeight - usedHeight
        end
    end

    local visibleIndex = 0
    for _, icon in ipairs(orderedIcons) do
        if isIconRouted(icon) then
            -- Routed icon: don't size or position here; the routing
            -- target (AF manager or CooldownTracker) owns both.
        else
            icon:SetSize(iconSize, iconHeight)
            icon:ClearAllPoints()
            if icon:IsShown() then
                if layoutMode == "vertical" then
                    private.Pixel.SetPoint(icon, "TOPLEFT", consumableContainer, "TOPLEFT", 0, -(alignOffsetY + visibleIndex * yStep))
                elseif layoutMode == "block" then
                    local col, row
                    if fillVertical then
                        row = visibleIndex % rows
                        col = math.floor(visibleIndex / rows)
                    else
                        col = visibleIndex % cols
                        row = math.floor(visibleIndex / cols)
                    end
                    local x = (mirrorX and (cols - 1 - col) or col) * xStep
                    local y = -((mirrorY and (rows - 1 - row) or row) * yStep)
                    private.Pixel.SetPoint(icon, "TOPLEFT", consumableContainer, "TOPLEFT", x, y)
                else
                    private.Pixel.SetPoint(icon, "TOPLEFT", consumableContainer, "TOPLEFT", alignOffsetX + visibleIndex * xStep, 0)
                end
                visibleIndex = visibleIndex + 1
            end
            if icon.Icon then
                icon.Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconHeight))
            end
            private.Util.ApplyIconBorder(icon)
        end
    end

    -- Update background visibility after layout
    local bgS = getSettings().background
    if bgS then private.Util.ApplyComponentBackground(consumableContainer, bgS) end
end

-- ---------------------------------------------------------------------------
-- OnUpdate handler
-- ---------------------------------------------------------------------------

---Periodically refresh cooldown sweeps on visible icons and detect
---cooldown transitions for glow effects.
local function onUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < UPDATE_INTERVAL then return end
    timeSinceLastUpdate = 0

    local inCombat = InCombatLockdown()
    local glowSettings = getSettings().glow
    local glowEnabled = glowSettings and glowSettings.enabled

    for _, icon in ipairs(orderedIcons) do
        if icon:IsShown() and icon.itemId then
            local start, duration, cdEnabled, cdDurObj, cdUnusable = getItemCooldown(icon.itemId)
            local hasRealCd = start and start > 0 and duration and duration > GCD_THRESHOLD and cdEnabled and cdEnabled ~= 0
            local isOnCooldown = cdDurObj ~= nil or cdUnusable or hasRealCd

            icon.Icon:SetDesaturated(isOnCooldown and not getVisualSettings(icon).no_desaturation)

            -- Every tick while on cooldown, not only on entering it: a
            -- Healthstone's next charge starts recharging with no off-cooldown
            -- tick in between. applyIconCooldown writes only a change.
            if isOnCooldown then
                if cdDurObj or hasRealCd then
                    applyIconCooldown(icon, hasRealCd and start or nil, duration, cdDurObj)
                end
            elseif icon.wasOnCooldown then
                applyIconCooldown(icon)
            end

            -- Persistent "ready in M+" glow: independent of combat state.
            -- When the player is inside an active keystone and a tracked
            -- potion is off cooldown, keep the pulse glow running until
            -- the item is used or the player leaves the keystone.
            local categoryAllowed = not glowSettings or (not glowSettings.combat_potions_only or icon.category == "combat")
            local persistentReady = glowEnabled
                and glowSettings.ready_in_mplus_enabled
                and glowSettings.pulse_enabled
                and categoryAllowed
                and (not isOnCooldown)
                and isInActiveMythicPlus()

            if persistentReady then
                -- StartPulse is idempotent (guards against re-Play), safe every tick.
                private.GlowEffect.StartPulse(icon, 0)
            elseif icon.persistentReady then
                -- Was persistently ready last tick, no longer — stop the infinite pulse.
                private.GlowEffect.StopPulse(icon)
            end
            icon.persistentReady = persistentReady

            -- Glow transition detection (combat-only)
            if glowEnabled and inCombat then
                local glowThisIcon = not glowSettings.combat_potions_only or icon.category == "combat"
                if glowThisIcon then
                    if icon.wasOnCooldown and not isOnCooldown then
                        -- Cooldown just finished during combat
                        private.GlowEffect.StopApproaching(icon)
                        if glowSettings.flash_enabled then
                            private.GlowEffect.PlayFlash(icon)
                        end
                        if glowSettings.pulse_enabled and not persistentReady then
                            private.GlowEffect.StartPulse(icon, glowSettings.pulse_duration)
                        end
                    elseif not icon.wasOnCooldown and isOnCooldown then
                        -- Item was just used; stop all glows
                        private.GlowEffect.StopAll(icon)
                    end
                    -- Approaching-ready detection: subtle glow when cooldown is nearly done
                    if isOnCooldown and glowSettings.approaching_enabled and glowSettings.approaching_time > 0 then
                        local remaining = (start + duration) - GetTime()
                        if remaining > 0 and remaining <= glowSettings.approaching_time then
                            private.GlowEffect.StartApproaching(icon)
                        else
                            private.GlowEffect.StopApproaching(icon)
                        end
                    end
                    -- Check pulse timer expiry (skip while persistent-ready keeps it alive)
                    if not persistentReady and private.GlowEffect.IsPulseExpired(icon) then
                        private.GlowEffect.StopPulse(icon)
                    end
                end
                -- Low health border glow: health/healthstone icons get a red
                -- pulsing border when the player's health drops below the
                -- configured threshold and the item is off cooldown.
                -- The animation plays during combat (non-secret gating); its
                -- wrapper alpha is driven by a secret health curve value via
                -- UnitHealthPercent() + step curve → SetAlpha().
                if glowSettings.low_health_enabled
                    and (icon.category == "health" or icon.category == "healthstone")
                then
                    if not isOnCooldown then
                        private.GlowEffect.StartBorder(icon)
                        local curve = getLowHealthCurve(glowSettings.low_health_pct or 35)
                        local alpha = UnitHealthPercent("player", true, curve)
                        private.GlowEffect.SetBorderAlpha(icon, alpha)
                    else
                        private.GlowEffect.StopBorder(icon)
                    end
                end
                -- Active buff glow: show a green border while a combat
                -- potion's buff effect is running. Duration is auto-derived
                -- from the item's spell description; icons without a
                -- parseable duration are skipped.
                if glowSettings.active_enabled and icon.activeBuffDuration then
                    if not icon.wasOnCooldown and isOnCooldown then
                        -- Item just used — start active timer
                        icon.activeBuffExpiry = GetTime() + icon.activeBuffDuration
                    end
                    if icon.activeBuffExpiry and GetTime() < icon.activeBuffExpiry then
                        private.GlowEffect.StartActive(icon)
                    else
                        icon.activeBuffExpiry = nil
                        private.GlowEffect.StopActive(icon)
                    end
                end
            elseif not inCombat and private.GlowEffect.HasGlow(icon) then
                if persistentReady then
                    -- Keep the persistent pulse alive; clear everything else.
                    private.GlowEffect.StopApproaching(icon)
                    private.GlowEffect.StopBorder(icon)
                    private.GlowEffect.StopActive(icon)
                else
                    private.GlowEffect.StopAll(icon)
                end
            end

            icon.wasOnCooldown = isOnCooldown
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event handler
-- ---------------------------------------------------------------------------

---The families shown before a bag refresh, in order, for the change test
---below.  Reused across events.
---@type string[]
local previousFamilies = {}

---Handle bag changes, cooldown updates, and spec changes.
local function onEvent(self, event, ...)
    if event == "BAG_UPDATE_DELAYED" then
        -- Once per batch (BAG_UPDATE fires once per bag), and a relayout only
        -- when the set of shown icons changed: a potion count dropping from 20
        -- to 19 moves nothing, and refreshAllIcons has already redrawn it.
        -- Every bag event used to run a full Anchor.Refresh plus the Additional
        -- Frame relayout: 757 of them in two minutes of a /cueperf capture,
        -- ~16 ms each (profiled).
        local count = #orderedIcons
        for i = 1, count do previousFamilies[i] = orderedIcons[i].familyKey end
        for i = #previousFamilies, count + 1, -1 do previousFamilies[i] = nil end
        slotCacheDirty = true
        rebuildSlotCache()
        refreshAllIcons()
        local changed = #orderedIcons ~= count
        if not changed then
            for i = 1, count do
                if orderedIcons[i].familyKey ~= previousFamilies[i] then
                    changed = true
                    break
                end
            end
        end
        if not changed then return end
        applyLayout()
        -- Icon count changed, so the frame size did too
        private.Anchor.Refresh()
        -- Re-layout additional frames with routed consumable categories:
        -- applyLayout skips routed icons, so an icon that became active via
        -- a bag change is otherwise never positioned by its routing target.
        if private.AdditionalFrameManager and private.AdditionalFrameManager.OnAddonIconRefresh then
            private.AdditionalFrameManager.OnAddonIconRefresh()
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        -- Cooldown changes are picked up by the OnUpdate tick (0.2s).
        -- Only force-update when an item transitions to on-cooldown so the
        -- sweep starts immediately without waiting for the next tick.
        for _, icon in ipairs(orderedIcons) do
            if icon:IsShown() and icon.itemId then
                local start, duration, cdEnabled, cdDurObj, cdUnusable = getItemCooldown(icon.itemId)
                local hasRealCd = start and start > 0 and duration and duration > GCD_THRESHOLD and cdEnabled and cdEnabled ~= 0
                local isOnCooldown = cdDurObj ~= nil or cdUnusable or hasRealCd
                if isOnCooldown and not icon.wasOnCooldown and (cdDurObj or hasRealCd) then
                    applyIconCooldown(icon, hasRealCd and start or nil, duration, cdDurObj)
                end
            end
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec change may affect mana auto-hide and available consumables
        slotCacheDirty = true
        consumableTracker.Refresh()
        private.Anchor.Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Component interface
-- ---------------------------------------------------------------------------

consumableTracker.Initialize = function()
    -- Pre-cache item data so localized names are available when Options opens
    for _, family in ipairs(CONSUMABLE_FAMILIES) do
        C_Item.RequestLoadItemDataByID(family.itemIds[#family.itemIds])
    end

    -- Create the container frame (plain Frame positioned by the anchoring system)
    consumableContainer = CreateFrame("Frame", "CUE_ConsumableTracker", UIParent)
    consumableContainer:SetSize(110, 50)

    -- Register events — only when enabled at load time. OnEnable/OnDisable
    -- maintain registration state at runtime.
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    if getEnabled() then
        eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end

    -- OnUpdate for cooldown sweep animation
    consumableContainer:SetScript("OnUpdate", onUpdate)

    -- No OnEnterCombat refresh: at PLAYER_REGEN_DISABLED the lockdown has not
    -- started, so it redrew the pre-combat state already on screen, in the pull
    -- frame.
    private.Callback.Register("OnLeaveCombat", function()
        for _, icon in pairs(consumableIcons) do
            private.GlowEffect.StopAll(icon)
            icon.wasOnCooldown = nil
            icon.activeBuffExpiry = nil
            icon.DurationText:Hide()
        end
        consumableTracker.Refresh()
    end)

    consumableTracker.Refresh()
end

consumableTracker.GetFrame = function()
    return consumableContainer
end

---Stop all active glow effects on every consumable icon.
---Used by EditMode when the glow master toggle is disabled.
consumableTracker.StopAllGlows = function()
    for _, icon in pairs(consumableIcons) do
        private.GlowEffect.StopAll(icon)
        icon.wasOnCooldown = nil
        icon.activeBuffExpiry = nil
        icon.DurationText:Hide()
    end
end

---Returns true if any consumable icons are routed to additional frames.
---When true, the container must stay alive (shown at alpha 0) even when
---the component is disabled, so OnUpdate keeps running for routed icons
---and SetIgnoreParentAlpha can render them independently.
---@return boolean
local function hasRoutedIcons()
    local afm = private.AdditionalFrameManager
    if afm then
        for _, catID in pairs(CONSUMABLE_CATEGORY_IDS) do
            if afm.IsSpellRouted(catID, "Consumable") then
                return true
            end
        end
    end
    -- Also check if any icon is routed to CooldownTracker
    local ct = private.CooldownTracker
    if ct and ct.IsIconRoutedHere then
        for _, icon in ipairs(orderedIcons) do
            if ct.IsIconRoutedHere(icon) then return true end
        end
    end
    return false
end

---A font edit made while hidden waits for the Refresh that shows the icons:
---the pass that reveals them carries no font pass.
local fontsOwed = false

consumableTracker.Refresh = function()
    if not consumableContainer then return end
    if private.fontsDirty then fontsOwed = true end
    rebuildSlotCache()

    local shouldShow = (getEnabled() or private.isEditMode)
        and private.Anchor.IsVisibleForComponent(consumableTracker.name)
    if shouldShow then
        consumableContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(consumableTracker.name))
        consumableContainer:Show()
        -- Apply font profiles only when settings may have changed
        if fontsOwed then
            fontsOwed = false
            local settings = getSettings()
            for _, icon in pairs(consumableIcons) do
                if settings.count_font then
                    private.Util.ApplyFontProfile(icon.Count, settings.count_font, icon)
                end
                if settings.duration_font then
                    private.Util.ApplyFontProfile(icon.DurationText, settings.duration_font, icon)
                end
                if settings.keybind_font and icon.KeybindText then
                    private.Util.ApplyFontProfile(icon.KeybindText, settings.keybind_font, icon)
                end
            end
        end
        refreshAllIcons()
    elseif hasRoutedIcons() then
        -- Disabled but has routed icons: keep container alive at alpha 0.
        -- Non-routed icons inherit alpha 0 (invisible); routed icons use
        -- SetIgnoreParentAlpha(true) set by the AF manager.
        consumableContainer:SetAlpha(0)
        consumableContainer:Show()
        refreshAllIcons()
    else
        consumableContainer:Hide()
    end

    -- Keybind text: Util's shared watcher invalidates the keybind cache and
    -- fires OnKeybindsChanged once per burst of binding / action-bar changes.
    if not keybindEventsRegistered then
        keybindEventsRegistered = true
        private.Callback.Register("OnKeybindsChanged", refreshAllIcons)
    end

    applyLayout()

    -- Notify AF manager that consumable icons may have changed
    if private.AdditionalFrameManager and private.AdditionalFrameManager.OnAddonIconRefresh then
        private.AdditionalFrameManager.OnAddonIconRefresh()
    end
end

consumableTracker.OnEnable = function()
    if consumableContainer then
        eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        consumableContainer:SetAlpha(private.Anchor.GetEffectiveAlpha(consumableTracker.name))
        consumableContainer:Show()
        consumableTracker.Refresh()
    end
end

consumableTracker.OnDisable = function()
    if consumableContainer then
        eventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        eventFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        if hasRoutedIcons() then
            consumableContainer:SetAlpha(0)
        else
            consumableContainer:Hide()
        end
    end
end

consumableTracker.GetComponentName = function()
    return consumableTracker.name
end

---Return all active icon frames for a given category ID.
---Used by AdditionalFrameManager to collect routed consumable icons.
---@param categoryID number  stable category ID (1=combat, 2=health, 3=mana, 4=healthstone, 5=utility)
---@return frame[]
consumableTracker.GetIconsByCategory = function(categoryID)
    local catKey = CONSUMABLE_ID_TO_CATEGORY[categoryID]
    if not catKey then return {} end
    local result = {}
    for _, icon in ipairs(orderedIcons) do
        if icon.category == catKey then
            result[#result + 1] = icon
        end
    end
    return result
end

---Return the stable category ID mapping (category string → numeric ID).
---@return table<string, number>
consumableTracker.GetCategoryIDs = function()
    return CONSUMABLE_CATEGORY_IDS
end

---ConsumableTracker always uses its own computed content width (from icon_size and layout)
---rather than inheriting the anchor parent's width via dual anchors.
consumableTracker.GetWantsContentWidth = function()
    return true
end

consumableTracker.IsCollapsed = function()
    for _, icon in ipairs(orderedIcons) do
        if icon:IsShown() then return false end
    end
    return true
end

consumableTracker.GetComponentSize = function()
    local settings = getSettings()
    local iconLimit = getEffectiveIconLimit()

    if iconLimit <= 0 then
        return 0, 0
    end

    local iconSize = settings.icon_size
    local iconOffset = settings.icon_offset
    local layoutMode = settings.layout
    local iconHeight = (settings.icon_height and settings.icon_height > 0) and math.floor(settings.icon_height) or iconSize

    if layoutMode == "vertical" then
        return iconSize, iconLimit * iconHeight + (iconLimit - 1) * iconOffset
    elseif layoutMode == "block" then
        local ap = settings.anchor_profile
        local cols, rows = getBlockGridParams(settings.block_direction or "horizontal", ap.anchor_side, ap.anchor_parent, iconLimit)
        return cols * iconSize + math.max(cols - 1, 0) * iconOffset,
               rows * iconHeight + math.max(rows - 1, 0) * iconOffset
    else
        return iconLimit * iconSize + (iconLimit - 1) * iconOffset, iconHeight
    end
end

consumableTracker.ContentLayout = function()
    rebuildSlotCache()
    refreshAllIcons()
    applyLayout()
end

private.ConsumableTracker = consumableTracker
private.ComponentManager.RegisterComponent("ConsumableTracker", consumableTracker)
