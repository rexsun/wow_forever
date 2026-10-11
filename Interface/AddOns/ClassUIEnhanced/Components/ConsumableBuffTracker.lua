
--[[
    ConsumableBuffTracker component.
    Displays status icons for long-duration consumable buffs — flasks, food,
    augment runes, weapon oils, weapon stones, and (WoW Forever) shaman weapon
    imbues and rogue poisons. Each category shows a single
    icon with remaining duration (or a desaturated "missing" state with glow).

    Detection:
    - Flask/Food/Rune: aura-based via C_UnitAuras.GetPlayerAuraBySpellID or
      C_UnitAuras.GetAuraDataBySpellName (fallback for unknown spell IDs).
    - Oil/Weapon buff: weapon enchant presence via
      C_PaperDollInfo.GetTemporaryEnchantmentInfo.
      Per-slot: one icon per equipped weapon slot for dual wielders.
    - Imbue (WoW Forever): C_Item.GetWeaponEnchantInfo, by enchant ID
      (IMBUES). A Forever imbue has no aura, only the enchant, and the call
      above does not report it.
    - Poison (WoW Forever): the same call, by enchant ID (POISONS). A Forever
      poison is a bag item whose use puts an enchant on the weapon.
    - MoP Classic: imbues from the call above by enchant ID; poisons are auras
      on the rogue (detection "spell_aura", one icon per poison group).
    - The tables are per game client, picked at load (#27).

    Duration display uses native CooldownFrame:
    - Aura: SetCooldownFromDurationObject (secret-safe, engine-driven).
    - Weapon enchant: SetCooldown with non-secret milliseconds from API.

    Icons are SecureActionButtons for click-to-use out of combat.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field ConsumableBuffTracker consumablebufftracker

---@class consumablebufftracker : component

---@type consumablebufftracker
---@diagnostic disable-next-line: missing-fields
local comp = {}

comp.name = "ConsumableBuffTracker"

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local INVSLOT_MAINHAND = 16
local INVSLOT_OFFHAND = 17
local WEAPON_CLASS_ID = Enum.ItemClass.Weapon
-- Oils and stones: 2 hours on retail, 30 minutes on every classic client (DB2
-- SpellItemEnchantment.Duration on Forever, the enchant effect's base points 1799
-- on Era, TBC and Wrath).
local WEAPON_ENCHANT_ASSUMED_DURATION = private.ClientScope.CLIENT == "retail" and 7200 or 1800

---Weapon subclass IDs for stone auto-selection.
local BLUNT_SUBCLASSES = { [4] = true, [5] = true, [10] = true, [13] = true } -- maces, staves, fist
local BLADED_SUBCLASSES = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true } -- axes, polearms, swords, warglaives, daggers
local GATHERING_SUBCLASSES = { [20] = true } -- fishing pole

---@class buff_category
---@field key string
---@field detection "aura"|"weapon_enchant"|"spell_aura"
---@field per_slot boolean
---@field auraSpells? table<number, number> spell ID → item ID (for icon lookup)
---@field spellName? string fallback aura name (for GetAuraDataBySpellName)
---@field spellNames? string[] fallback aura names (checked in order after auraSpells)
---@field items? number[] item IDs for bag scan / click-to-use (priority order)
---@field stones? table<string, {itemIds: number[], subClasses: table<number, boolean>}> per weapon group, best stone first
---@field groups? number[][] spell_aura only: one icon per group, any of its spells' auras counts
---@field enchants? table<number, true> weapon_enchant only: the enchant IDs this category's items put on a weapon; nil = any temporary enchant counts
---@field fallbackIcon? number

-- One table per game client (#27), picked at load: the consumables differ,
-- and a shared table would list every client's items in each one's Options.

---@type buff_category[]
local RETAIL_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [1235057] = 241321, -- Flask of Thalassian Resistance
            [1235110] = 241325, -- Flask of the Blood Knights
            [1235108] = 241322, -- Flask of the Magisters
            [1235111] = 241326, -- Flask of the Shattered Sun
        },
        spellNames = {
            "Flask of Thalassian Resistance",
            "Flask of the Blood Knights",
            "Flask of the Magisters",
            "Flask of the Shattered Sun",
        },
        items = { 241324, 241325, 245930, 241322, 241323, 245932, 241326, 241327, 241320, 241321, 245927 },
        fallbackIcon = C_Item.GetItemIconByID(241325),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [1278895] = 266985, -- Hearty Silvermoon Parade
            [1278929] = 266996, -- Hearty Harandar Celebration
        },
        spellNames = {
            "Hearty Well Fed",
            "Well Fed",
        },
        items = {
            -- Hearty master tier (persists through death, best stat)
            268679, -- Hearty Impossibly Royal Roast
            242747, -- Hearty Royal Roast
            267000, -- Hearty Flora Frenzy
            242746, -- Hearty Champion's Bento
            -- Master tier (+65 stat)
            255847, -- Impossibly Royal Roast
            242275, -- Royal Roast
            255848, -- Flora Frenzy
            242274, -- Champion's Bento
            -- Advanced tier (+59 single stat)
            242287, -- Arcano Cutlets (Crit)
            242283, -- Sun-Seared Lumifin (Crit)
            242278, -- Tasty Smoked Tetra (Crit)
            242277, -- Crimson Calamari (Haste)
            242286, -- Fel-Kissed Filet (Haste)
            242282, -- Null and Void Plate (Haste)
            242281, -- Glitter Skewers (Mastery)
            242285, -- Warped Wise Wings (Mastery)
            242279, -- Baked Lucky Loa
            242284, -- Void-Kissed Fish Rolls
            242276, -- Braised Blood Hunter (Vers)
            242280, -- Buttered Root Crab (Vers)
            -- Hearty feasts (persists through death)
            266985, -- Hearty Silvermoon Parade
            266996, -- Hearty Harandar Celebration
            266986, -- Hearty Quel'dorei Medley
            242745, -- Hearty Blooming Feast
            -- Feasts
            255845, -- Silvermoon Parade
            255846, -- Harandar Celebration
            242272, -- Quel'dorei Medley
            242273, -- Blooming Feast
        },
        fallbackIcon = C_Item.GetItemIconByID(242275),
    },
    {
        key = "rune",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [1264426] = 259085, -- Void-Touched Augment Rune
        },
        spellNames = {
            "Void-Touched Augment Rune",
        },
        items = { 259085 },
        fallbackIcon = C_Item.GetItemIconByID(259085),
    },
    {
        key = "oil",
        detection = "weapon_enchant",
        per_slot = true,
        items = {
            -- Thalassian Phoenix Oil (rank 2, rank 1)
            243734, 243733,
            -- Smuggler's Enchanted Edge (rank 2, rank 1)
            243738, 243737,
            -- Oil of Dawn (rank 2, rank 1)
            243736, 243735,
        },
        fallbackIcon = C_Item.GetItemIconByID(243733),
    },
    {
        key = "weapon_buff",
        detection = "weapon_enchant",
        per_slot = true,
        stones = {
            blunt = { itemIds = { 237369 }, subClasses = BLUNT_SUBCLASSES },
            bladed = { itemIds = { 237371 }, subClasses = BLADED_SUBCLASSES },
            gathering = { itemIds = { 237373 }, subClasses = GATHERING_SUBCLASSES },
        },
        items = { 237371, 237369, 237373 },
        fallbackIcon = C_Item.GetItemIconByID(237371),
    },
    {
        -- Textures come from the imbue spell; no bag items.
        key = "imbue",
        detection = "weapon_enchant",
        per_slot = true,
    },
    {
        -- Textures come from the poison items.
        key = "poison",
        detection = "weapon_enchant",
        per_slot = true,
    },
}

-- WoW Forever.  Every ID checked in that client's DB2 (build 1.60.1.70245).
-- Flask and food auras are the buffs the player carries, not the craft spells.
-- Forever reworked food: most foods share one "Well Fed" aura per stat.
---@type buff_category[]
local FOREVER_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [17626] = 13510, -- Flask of the Titans
            [17627] = 13511, -- Distilled Wisdom
            [17628] = 13512, -- Supreme Power
            [17629] = 13513, -- Chromatic Resistance
        },
        spellNames = { "Flask of the Titans", "Distilled Wisdom", "Supreme Power", "Chromatic Resistance" },
        items = { 13510, 13512, 13511, 13513 },
        fallbackIcon = C_Item.GetItemIconByID(13510),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [1248422] = 20452,  -- Well Fed (Strength): Smoked Desert Dumplings
            [1248420] = 18045,  -- Well Fed (Agility): Tender Wolf Steak
            [1248421] = 18254,  -- Well Fed (Intellect): Runn Tum Tuber Surprise
            [1249521] = 13930,  -- Well Fed (Intellect): Filet of Redgill
            [1248406] = 12218,  -- Well Fed (Stamina): Monster Omelet
            [1249520] = 13931,  -- Well Fed (Spell Damage): Nightfin Soup, Sagefish Delight, Baked Salmon
            [1249523] = 13928,  -- Well Fed (Crit): Grilled Squid, Hot Smoked Bass
            [1249519] = 13934,  -- Well Fed (Attack Power): Mightfish Steak, Poached Sunscale Salmon
            [1249927] = 249866, -- Well Fed (Healing): Royal Tea
            [1249926] = 249871, -- Well Fed (Spirit): Venomous Smoothie
            [25661]   = 21023,  -- Increased Stamina: Dirge's Kickin' Chimaerok Chops
        },
        spellNames = { "Well Fed", "Increased Stamina" },
        items = { 21023, 20452, 13928, 13931, 21217, 13934, 18254, 18045, 12218, 13935, 13929, 13932 },
        fallbackIcon = C_Item.GetItemIconByID(13928),
    },
    {
        key = "oil",
        detection = "weapon_enchant",
        per_slot = true,
        items = {
            20749, 20748,        -- Brilliant Wizard Oil, Brilliant Mana Oil
            20750, 20747,        -- Wizard Oil, Lesser Mana Oil
            20746, 20745, 20744, -- Lesser Wizard Oil, Minor Mana Oil, Minor Wizard Oil
        },
        fallbackIcon = C_Item.GetItemIconByID(20749),
    },
    {
        key = "weapon_buff",
        detection = "weapon_enchant",
        per_slot = true,
        -- Elemental Sharpening Stone fits every melee weapon (SpellEquippedItems).
        stones = {
            blunt = { itemIds = { 18262, 12643, 7965, 3241, 3240, 3239 }, subClasses = BLUNT_SUBCLASSES },   -- Dense … Rough Weightstone
            bladed = { itemIds = { 18262, 12404, 7964, 2871, 2863, 2862 }, subClasses = BLADED_SUBCLASSES }, -- Dense … Rough Sharpening Stone
        },
        items = { 18262, 12404, 12643 },
        fallbackIcon = C_Item.GetItemIconByID(12404),
    },
    { key = "imbue", detection = "weapon_enchant", per_slot = true },
    { key = "poison", detection = "weapon_enchant", per_slot = true },
}

-- MoP Classic.  Every ID checked in that client's DB2 (build 5.5.4.70032)
-- unless marked otherwise.  MoP has no augment rune, oil or weapon stone, and
-- its rogue poisons are auras on the rogue, not weapon enchants.
---@type buff_category[]
local MISTS_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [105689] = 76084, -- Flask of Spring Blossoms
            [105691] = 76085, -- Flask of the Warm Sun
            [105693] = 76086, -- Flask of Falling Leaves
            [105694] = 76087, -- Flask of the Earth
            [105696] = 76088, -- Flask of Winter's Bite
            [127230] = 86569, -- Visions of Insanity (Crystal of Insanity)
            -- Alchemist's Flask: its use spell (105617) is a script that picks
            -- one of these by highest stat; its text reads the buff's length
            -- from 79639, and all three are 2 h stat auras.
            [79638] = 75525,  -- Enhanced Strength
            [79639] = 75525,  -- Enhanced Agility
            [79640] = 75525,  -- Enhanced Intellect
        },
        spellNames = { "Flask of Spring Blossoms", "Flask of the Warm Sun", "Flask of Falling Leaves",
            "Flask of the Earth", "Flask of Winter's Bite", "Visions of Insanity" },
        items = { 76084, 76085, 76086, 76087, 76088, 75525, 86569 },
        fallbackIcon = C_Item.GetItemIconByID(76085),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        -- Every one is named "Well Fed".  Banquets only place a table; their
        -- text reads the buff from these dishes' own auras (104273, 104274),
        -- so a banquet's buff is one of the entries below.
        auraSpells = {
            [104272] = 74646,  -- Black Pepper Ribs and Shrimp
            [104275] = 74648,  -- Sea Mist Rice Noodles
            [104277] = 74650,  -- Mogu Fish Stew
            [104280] = 74653,  -- Steamed Crab Surprise
            [104283] = 74656,  -- Chun Tian Spring Rolls
            [146804] = 101750, -- Fluffy Silkfeather Omelet
            [146805] = 101746, -- Seasoned Pomfruit Slices
            [146806] = 101748, -- Spiced Blossom Soup
            [146807] = 101747, -- Farmer's Delight
            [146808] = 101749, -- Stuffed Lushrooms
            [146809] = 101745, -- Mango Ice
            [104271] = 74645,  -- Eternal Blossom Fish
            [104274] = 74647,  -- Valley Stir Fry
            [104276] = 74649,  -- Braised Turtle
            [104279] = 74652,  -- Fire Spirit Salmon
            [104282] = 74655,  -- Twin Fish Platter
            [104267] = 74642,  -- Charbroiled Tiger Steak
            [104273] = 74643,  -- Sauteed Carrots
            [104264] = 74644,  -- Swirling Mist Soup
            [104278] = 74651,  -- Shrimp Dumplings
            [104281] = 74654,  -- Wildfowl Roast
            [125113] = 86073,  -- Spicy Salmon
            [125115] = 86074,  -- Spicy Vegetable Chips
            [125106] = 86070,  -- Wildfowl Ginseng Soup
            [125108] = 86069,  -- Rice Pudding
            [105226] = 75038,  -- Mad Brewer's Breakfast
        },
        spellNames = { "Well Fed" },
        items = {
            74646, 74648, 74650, 74653, 74656,                -- 300 / 450 tier
            101750, 101746, 101748, 101747, 101749, 101745,   -- 5.4 300 / 450 tier
            86073, 86074,                                     -- 300 rating
            74645, 74647, 74649, 74652, 74655, 86070, 86069,  -- 275 / 415 tier
            74642, 74643, 74644, 74651, 74654,                -- 250 / 375 tier
            75016, 87228, 87232, 87236, 87240, 87244, 87248,  -- Great Pandaren Banquet, Great Banquets
            74919, 87226, 87230, 87234, 87238, 87242, 87246,  -- Pandaren Banquet, Banquets
        },
        fallbackIcon = C_Item.GetItemIconByID(74646),
    },
    { key = "imbue", detection = "weapon_enchant", per_slot = true },
    {
        -- One icon per group: the lethal poison, then the non-lethal one.
        key = "poison",
        detection = "spell_aura",
        per_slot = false,
        groups = {
            { 2823, 8679 },                   -- Deadly, Wound Poison
            { 3408, 5761, 108211, 108215 },   -- Crippling, Mind-numbing, Leeching, Paralytic Poison
        },
    },
}

-- Classic Era, TBC and Wrath.  Every ID checked in that client's DB2 (builds
-- 1.15.9.70003, 2.5.6.69795, 3.80.2.70177): a flask's buff is its item's use
-- spell, a food's is the spell its eating aura triggers (nested one level under
-- "Refreshment" on Wrath).  Feasts only place an object, so their buff is not
-- in the data; Wrath's is named "Well Fed" and the name fallback catches it.
-- A hand holds one temporary enchant of any kind on these clients, so oils and
-- stones list their `enchants` and a poison or imbue does not count as one.
-- Elixirs are not tracked.
---@type buff_category[]
local ERA_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [17626] = 13510, -- Flask of the Titans
            [17627] = 13511, -- Flask of Distilled Wisdom
            [17628] = 13512, -- Flask of Supreme Power
            [17629] = 13513, -- Flask of Chromatic Resistance
        },
        items = {
            13510, 13511, 13512, 13513,
        },
        fallbackIcon = C_Item.GetItemIconByID(13510),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [25661] = 21023, -- Increased Stamina: Dirge's Kickin' Chimaerok Chops
            [18125] = 13810, -- Blessed Sunfruit: Blessed Sunfruit
            [18191] = 11950, -- Increased Stamina: Windblossom Berries
            [22730] = 18254, -- Increased Intellect: Runn Tum Tuber Surprise
            [24799] = 20452, -- Well Fed: Smoked Desert Dumplings
            [19710] = 12216, -- Well Fed: Spiced Chili Crab
            [18192] = 13928, -- Increased Agility: Grilled Squid
            [18193] = 13929, -- Increased Spirit: Hot Smoked Bass
            [18194] = 13931, -- Mana Regeneration: Nightfin Soup
            [18222] = 13932, -- Health Regeneration: Poached Sunscale Salmon
            [19709] = 3729, -- Well Fed: Soothing Turtle Bisque
            [19708] = 1017, -- Well Fed: Seasoned Wolf Kabob
            [19706] = 724, -- Well Fed: Goretusk Liver Pie
            [19705] = 5474, -- Well Fed: Roasted Kodo Meat
        },
        spellNames = { "Well Fed", "Blessed Sunfruit", "Health Regeneration", "Increased Agility", "Increased Intellect", "Increased Spirit", "Increased Stamina", "Mana Regeneration" },
        items = {
            21023, 11950, 13810, 13934, 18254, 20452, 12216, 16971,
            18045, 13927, 13928, 13929, 13931, 13932, 12215, 17222,
        },
        fallbackIcon = C_Item.GetItemIconByID(21023),
    },
    {
        key = "oil",
        detection = "weapon_enchant",
        per_slot = true,
        items = { 20749, 20748, 20750, 20747, 20746, 20745, 20744 },
        enchants = { [25] = true, [26] = true, [2623] = true, [2624] = true, [2625] = true, [2626] = true, [2627] = true, [2628] = true, [2629] = true, [2685] = true },
        fallbackIcon = C_Item.GetItemIconByID(20749),
    },
    {
        key = "weapon_buff",
        detection = "weapon_enchant",
        per_slot = true,
        stones = {
            blunt = { itemIds = { 18262, 12643, 7965, 3241, 3240, 3239 }, subClasses = BLUNT_SUBCLASSES },
            bladed = { itemIds = { 18262, 12404, 7964, 2871, 2863, 2862 }, subClasses = BLADED_SUBCLASSES },
        },
        items = { 18262, 18262, 18262 },
        enchants = { [13] = true, [14] = true, [19] = true, [20] = true, [21] = true, [40] = true, [483] = true, [484] = true, [1643] = true, [1703] = true, [2506] = true, [2684] = true },
        fallbackIcon = C_Item.GetItemIconByID(18262),
    },
    { key = "imbue", detection = "weapon_enchant", per_slot = true },
    { key = "poison", detection = "weapon_enchant", per_slot = true },
}

---@type buff_category[]
local TBC_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [28520] = 22854, -- Flask of Relentless Assault
            [28521] = 22861, -- Flask of Blinding Light
            [28540] = 22866, -- Flask of Pure Death
            [28518] = 22851, -- Flask of Fortification
            [28519] = 22853, -- Flask of Mighty Restoration
            [42735] = 33208, -- Flask of Chromatic Wonder
            [41608] = 32901, -- Shattrath Flask of Relentless Assault
            [46839] = 35717, -- Shattrath Flask of Blinding Light
            [46837] = 35716, -- Shattrath Flask of Pure Death
            [41609] = 32898, -- Shattrath Flask of Fortification
            [41610] = 32899, -- Shattrath Flask of Mighty Restoration
            [41611] = 32900, -- Shattrath Flask of Supreme Power
            [40568] = 32596, -- Unstable Flask of the Elder
            [40575] = 32597, -- Unstable Flask of the Soldier
            [40572] = 32598, -- Unstable Flask of the Beast
            [40567] = 32599, -- Unstable Flask of the Bandit
            [40573] = 32600, -- Unstable Flask of the Physician
            [40576] = 32601, -- Unstable Flask of the Sorcerer
            [17626] = 13510, -- Flask of the Titans
            [17627] = 13511, -- Flask of Distilled Wisdom
            [17628] = 13512, -- Flask of Supreme Power
            [17629] = 13513, -- Flask of Chromatic Resistance
        },
        items = {
            22854, 22861, 22866, 22851, 22853, 33208, 32901, 35717,
            35716, 32898, 32899, 32900, 32596, 32597, 32598, 32599,
            32600, 32601, 13510, 13511, 13512, 13513,
        },
        fallbackIcon = C_Item.GetItemIconByID(22854),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [33256] = 30359, -- Well Fed: Oronok's Tuber of Strength
            [33257] = 33052, -- Well Fed: Fisherman's Feast
            [33261] = 30358, -- Well Fed: Oronok's Tuber of Agility
            [33263] = 30361, -- Well Fed: Oronok's Tuber of Spell Power
            [33268] = 30357, -- Well Fed: Oronok's Tuber of Healing
            [35272] = 33026, -- Well Fed: The Golden Link
            [43764] = 33872, -- Well Fed: Spicy Hot Talbuk
            [18191] = 24008, -- Increased Stamina: Dried Mushroom Rations
            [18193] = 24539, -- Increased Spirit: Marsh Lichen
            [24799] = 29292, -- Well Fed: Helboar Bacon
            [25661] = 21023, -- Increased Stamina: Dirge's Kickin' Chimaerok Chops
            [33254] = 27662, -- Well Fed: Feltail Delight
            [33259] = 27655, -- Well Fed: Ravager Dog
            [33265] = 27663, -- Well Fed: Blackened Sporefish
            [42293] = 32721, -- Well Fed: Skyguard Rations
            [45619] = 33867, -- Well Fed: Broiled Bloodfin
            [18125] = 13810, -- Blessed Sunfruit: Blessed Sunfruit
            [19711] = 33024, -- Well Fed: Pickled Sausage
            [22730] = 18254, -- Increased Intellect: Runn Tum Tuber Surprise
            [46687] = 35565, -- Well Fed: Juicy Bear Burger
            [46899] = 35563, -- Well Fed: Charred Bear Kabobs
            [19710] = 12216, -- Well Fed: Spiced Chili Crab
            [18192] = 13928, -- Increased Agility: Grilled Squid
            [18222] = 13932, -- Health Regeneration: Poached Sunscale Salmon
            [19709] = 3729, -- Well Fed: Soothing Turtle Bisque
            [19708] = 1017, -- Well Fed: Seasoned Wolf Kabob
            [19706] = 724, -- Well Fed: Goretusk Liver Pie
            [19705] = 5474, -- Well Fed: Roasted Kodo Meat
        },
        spellNames = { "Well Fed", "Blessed Sunfruit", "Health Regeneration", "Increased Agility", "Increased Intellect", "Increased Spirit", "Increased Stamina" },
        items = {
            30357, 30358, 30359, 30361, 33026, 33052, 33872, 34410,
            21023, 24008, 24009, 24539, 27655, 27657, 27658, 27659,
            27660, 27662, 27663, 27664, 27665, 27666, 27667, 30155,
            31672, 31673, 32721, 33025, 33867, 28501, 29292,
        },
        fallbackIcon = C_Item.GetItemIconByID(30357),
    },
    {
        key = "oil",
        detection = "weapon_enchant",
        per_slot = true,
        items = { 22522, 22521, 20749, 20748, 20750, 20747, 20746, 20745, 20744 },
        enchants = { [25] = true, [26] = true, [2623] = true, [2624] = true, [2625] = true, [2626] = true, [2627] = true, [2628] = true, [2629] = true, [2677] = true, [2678] = true, [2685] = true, [3265] = true },
        fallbackIcon = C_Item.GetItemIconByID(22522),
    },
    {
        key = "weapon_buff",
        detection = "weapon_enchant",
        per_slot = true,
        stones = {
            blunt = { itemIds = { 28421, 28420, 18262, 12643, 7965, 3241, 3240, 3239 }, subClasses = BLUNT_SUBCLASSES },
            bladed = { itemIds = { 23529, 23528, 18262, 12404, 7964, 2871, 2863, 2862 }, subClasses = BLADED_SUBCLASSES },
        },
        items = { 23529, 28421, 18262 },
        enchants = { [13] = true, [14] = true, [19] = true, [20] = true, [21] = true, [40] = true, [483] = true, [484] = true, [1643] = true, [1703] = true, [2506] = true, [2684] = true, [2712] = true, [2713] = true, [2954] = true, [2955] = true, [3266] = true },
        fallbackIcon = C_Item.GetItemIconByID(23529),
    },
    { key = "imbue", detection = "weapon_enchant", per_slot = true },
    { key = "poison", detection = "weapon_enchant", per_slot = true },
}

---@type buff_category[]
local WRATH_CATEGORIES = {
    {
        key = "flask",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [53760] = 46377, -- Flask of Endless Rage
            [54212] = 46378, -- Flask of Pure Mojo
            [53758] = 46379, -- Flask of Stoneblood
            [53755] = 46376, -- Flask of the Frost Wyrm
            [67016] = 47499, -- Flask of the North
            [67017] = 47499, -- Flask of the North
            [67018] = 47499, -- Flask of the North
            [53752] = 40079, -- Lesser Flask of Toughness
            [62380] = 44939, -- Lesser Flask of Resistance
            [28520] = 22854, -- Flask of Relentless Assault
            [28521] = 22861, -- Flask of Blinding Light
            [28540] = 22866, -- Flask of Pure Death
            [28518] = 22851, -- Flask of Fortification
            [28519] = 22853, -- Flask of Mighty Restoration
            [42735] = 33208, -- Flask of Chromatic Wonder
            [41608] = 32901, -- Shattrath Flask of Relentless Assault
            [46839] = 35717, -- Shattrath Flask of Blinding Light
            [46837] = 35716, -- Shattrath Flask of Pure Death
            [41609] = 32898, -- Shattrath Flask of Fortification
            [41610] = 32899, -- Shattrath Flask of Mighty Restoration
            [41611] = 32900, -- Shattrath Flask of Supreme Power
            [17626] = 13510, -- Flask of the Titans
            [17627] = 13511, -- Flask of Distilled Wisdom
            [17628] = 13512, -- Flask of Supreme Power
            [17629] = 13513, -- Flask of Chromatic Resistance
        },
        items = {
            46377, 46378, 46379, 46376, 47499, 40079, 44939, 22854,
            22861, 22866, 22851, 22853, 33208, 32901, 35717, 35716,
            32898, 32899, 32900, 13510, 13511, 13512, 13513,
        },
        fallbackIcon = C_Item.GetItemIconByID(46377),
    },
    {
        key = "food",
        detection = "aura",
        per_slot = false,
        auraSpells = {
            [53284] = 42779, -- Well Fed: Steaming Chicken Soup
            [57079] = 34762, -- Well Fed: Grilled Sculpin
            [57097] = 34763, -- Well Fed: Smoked Salmon
            [57100] = 34764, -- Well Fed: Poached Nettlefish
            [57102] = 42942, -- Well Fed: Baked Manta Ray
            [57107] = 34765, -- Well Fed: Pickled Fangtooth
            [57111] = 34748, -- Well Fed: Mammoth Meal
            [57139] = 34749, -- Well Fed: Shoveltusk Steak
            [57286] = 34750, -- Well Fed: Worm Delight
            [57288] = 34751, -- Well Fed: Roasted Worg
            [57291] = 34752, -- Well Fed: Rhino Dogs
            [57294] = 43268, -- Well Fed: Dalaran Clam Chowder
            [57325] = 34754, -- Well Fed: Mega Mammoth Meal
            [57327] = 34755, -- Well Fed: Tender Shoveltusk Steak
            [57329] = 34756, -- Well Fed: Spiced Worm Burger
            [57332] = 34757, -- Well Fed: Very Burnt Worg
            [57334] = 34758, -- Well Fed: Mighty Rhino Dogs
            [57356] = 42994, -- Well Fed: Rhinolicious Wormsteak
            [57358] = 42995, -- Well Fed: Hearty Rhino
            [57360] = 42996, -- Well Fed: Snapper Extreme
            [57363] = 42997, -- Well Fed: Blackened Worg Steak
            [57365] = 42998, -- Well Fed: Cuttlesteak
            [57367] = 42999, -- Well Fed: Blackened Dragonfin
            [57371] = 43000, -- Well Fed: Dragonfin Filet
            [57373] = 43001, -- Well Fed: Tracker Snacks
            [33256] = 30359, -- Well Fed: Oronok's Tuber of Strength
            [33257] = 33052, -- Well Fed: Fisherman's Feast
            [33261] = 30358, -- Well Fed: Oronok's Tuber of Agility
            [33263] = 30361, -- Well Fed: Oronok's Tuber of Spell Power
            [33268] = 30357, -- Well Fed: Oronok's Tuber of Healing
            [35272] = 33026, -- Well Fed: The Golden Link
            [43764] = 33872, -- Well Fed: Spicy Hot Talbuk
            [18191] = 24008, -- Increased Stamina: Dried Mushroom Rations
            [18193] = 24539, -- Increased Spirit: Marsh Lichen
            [24799] = 29292, -- Well Fed: Helboar Bacon
            [25661] = 21023, -- Increased Stamina: Dirge's Kickin' Chimaerok Chops
            [33254] = 27662, -- Well Fed: Feltail Delight
            [33259] = 27655, -- Well Fed: Ravager Dog
            [33265] = 27663, -- Well Fed: Blackened Sporefish
            [42293] = 32721, -- Well Fed: Skyguard Rations
            [45619] = 33867, -- Well Fed: Broiled Bloodfin
            [18125] = 13810, -- Blessed Sunfruit: Blessed Sunfruit
            [19711] = 33024, -- Well Fed: Pickled Sausage
            [22730] = 18254, -- Increased Intellect: Runn Tum Tuber Surprise
            [46687] = 35565, -- Well Fed: Juicy Bear Burger
            [46899] = 35563, -- Well Fed: Charred Bear Kabobs
            [19710] = 12216, -- Well Fed: Spiced Chili Crab
            [18192] = 13928, -- Increased Agility: Grilled Squid
            [18222] = 13932, -- Health Regeneration: Poached Sunscale Salmon
            [64057] = 33004, -- Well Fed: Clamlette Magnifique
            [19709] = 3729, -- Well Fed: Soothing Turtle Bisque
            [19708] = 1017, -- Well Fed: Seasoned Wolf Kabob
            [19706] = 724, -- Well Fed: Goretusk Liver Pie
            [19705] = 5474, -- Well Fed: Roasted Kodo Meat
        },
        spellNames = { "Well Fed", "Blessed Sunfruit", "Health Regeneration", "Increased Agility", "Increased Intellect", "Increased Spirit", "Increased Stamina" },
        items = {
            43015, 34753, 43478, 43480, 46887, 42779, 34748, 34749,
            34750, 34751, 34752, 34754, 34755, 34756, 34757, 34758,
            34762, 34763, 34764, 34765, 34766, 34767, 34768, 34769,
            42942, 42993, 42994, 42995, 42996, 42997, 42998, 42999,
            43000, 43001, 43268, 44953, 34125, 39691,
        },
        fallbackIcon = C_Item.GetItemIconByID(43015),
    },
    {
        key = "oil",
        detection = "weapon_enchant",
        per_slot = true,
        items = { 36900, 36899, 22522, 22521, 20749, 20748, 20750, 20747, 20746, 20745, 20744 },
        enchants = { [25] = true, [26] = true, [2623] = true, [2624] = true, [2625] = true, [2626] = true, [2627] = true, [2628] = true, [2629] = true, [2677] = true, [2678] = true, [3265] = true, [3298] = true, [3299] = true, [3592] = true },
        fallbackIcon = C_Item.GetItemIconByID(36900),
    },
    {
        key = "weapon_buff",
        detection = "weapon_enchant",
        per_slot = true,
        stones = {
            blunt = { itemIds = { 28421, 28420, 18262, 12643, 7965, 3241, 3240, 3239 }, subClasses = BLUNT_SUBCLASSES },
            bladed = { itemIds = { 23529, 23528, 18262, 12404, 7964, 2871, 2863, 2862 }, subClasses = BLADED_SUBCLASSES },
        },
        items = { 23529, 28421, 18262 },
        enchants = { [13] = true, [14] = true, [19] = true, [20] = true, [21] = true, [40] = true, [483] = true, [484] = true, [1643] = true, [1703] = true, [2506] = true, [2712] = true, [2713] = true, [2954] = true, [2955] = true, [3266] = true, [3593] = true },
        fallbackIcon = C_Item.GetItemIconByID(23529),
    },
    { key = "imbue", detection = "weapon_enchant", per_slot = true },
    { key = "poison", detection = "weapon_enchant", per_slot = true },
}

local CATEGORIES_BY_CLIENT = {
    retail = RETAIL_CATEGORIES, forever = FOREVER_CATEGORIES, mists = MISTS_CATEGORIES,
    era = ERA_CATEGORIES, tbc = TBC_CATEGORIES, wrath = WRATH_CATEGORIES,
}
local BUFF_CATEGORIES = CATEGORIES_BY_CLIENT[private.ClientScope.CLIENT] or {}

---Display order: the client's own categories, in the order it lists them.
local CATEGORY_ORDER = {}
for i, cat in ipairs(BUFF_CATEGORIES) do CATEGORY_ORDER[i] = cat.key end

local CATEGORY_LABELS = {
    flask = "BUFF_CAT_FLASK",
    food = "BUFF_CAT_FOOD",
    rune = "BUFF_CAT_RUNE",
    oil = "BUFF_CAT_OIL",
    weapon_buff = "BUFF_CAT_WEAPON_BUFF",
    imbue = "BUFF_CAT_IMBUE",
    poison = "BUFF_CAT_POISON",
}

---Individual trackable entries within categories (for per-item toggles).
---@class buff_entry_item
---@field key string unique key for tracked_buffs profile
---@field category string parent category key
---@field itemId number representative item ID (for name + icon)
---@field icon number cached icon texture
---@field variantIds? number[] alias item IDs (other quality ranks of the same consumable)

---@type buff_entry_item[]
local RETAIL_ENTRIES = {
    -- Flasks
    { key = "flask_of_thalassian_resistance", category = "flask", itemId = 241321, icon = C_Item.GetItemIconByID(241321) },
    { key = "flask_of_the_blood_knights", category = "flask", itemId = 241325, icon = C_Item.GetItemIconByID(241325) },
    { key = "flask_of_the_magisters", category = "flask", itemId = 241322, icon = C_Item.GetItemIconByID(241322) },
    { key = "flask_of_the_shattered_sun", category = "flask", itemId = 241326, icon = C_Item.GetItemIconByID(241326) },
    -- Rune
    { key = "void_touched_augment_rune", category = "rune", itemId = 259085, icon = C_Item.GetItemIconByID(259085) },
    -- Oils
    { key = "thalassian_phoenix_oil", category = "oil", itemId = 243733, icon = C_Item.GetItemIconByID(243733), variantIds = { 243734 } },
    { key = "smugglers_enchanted_edge", category = "oil", itemId = 243738, icon = C_Item.GetItemIconByID(243738), variantIds = { 243737 } },
    { key = "oil_of_dawn", category = "oil", itemId = 243736, icon = C_Item.GetItemIconByID(243736), variantIds = { 243735 } },
    -- Weapon Buffs
    { key = "refulgent_weightstone", category = "weapon_buff", itemId = 237369, icon = C_Item.GetItemIconByID(237369) },
    { key = "refulgent_whetstone", category = "weapon_buff", itemId = 237371, icon = C_Item.GetItemIconByID(237371) },
    { key = "refulgent_razorstone", category = "weapon_buff", itemId = 237373, icon = C_Item.GetItemIconByID(237373) },
}

---@type buff_entry_item[]
local FOREVER_ENTRIES = {
    -- Flasks
    { key = "flask_of_the_titans", category = "flask", itemId = 13510, icon = C_Item.GetItemIconByID(13510) },
    { key = "flask_of_distilled_wisdom", category = "flask", itemId = 13511, icon = C_Item.GetItemIconByID(13511) },
    { key = "flask_of_supreme_power", category = "flask", itemId = 13512, icon = C_Item.GetItemIconByID(13512) },
    { key = "flask_of_chromatic_resistance", category = "flask", itemId = 13513, icon = C_Item.GetItemIconByID(13513) },
    -- Oils
    { key = "wizard_oil", category = "oil", itemId = 20749, icon = C_Item.GetItemIconByID(20749), variantIds = { 20750, 20746, 20744 } },
    { key = "mana_oil", category = "oil", itemId = 20748, icon = C_Item.GetItemIconByID(20748), variantIds = { 20747, 20745 } },
    -- Weapon Buffs
    { key = "elemental_sharpening_stone", category = "weapon_buff", itemId = 18262, icon = C_Item.GetItemIconByID(18262) },
    { key = "sharpening_stone", category = "weapon_buff", itemId = 12404, icon = C_Item.GetItemIconByID(12404), variantIds = { 7964, 2871, 2863, 2862 } },
    { key = "weightstone", category = "weapon_buff", itemId = 12643, icon = C_Item.GetItemIconByID(12643), variantIds = { 7965, 3241, 3240, 3239 } },
}

---@type buff_entry_item[]
local MISTS_ENTRIES = {
    -- Flasks
    { key = "flask_of_spring_blossoms", category = "flask", itemId = 76084, icon = C_Item.GetItemIconByID(76084) },
    { key = "flask_of_the_warm_sun", category = "flask", itemId = 76085, icon = C_Item.GetItemIconByID(76085) },
    { key = "flask_of_falling_leaves", category = "flask", itemId = 76086, icon = C_Item.GetItemIconByID(76086) },
    { key = "flask_of_the_earth", category = "flask", itemId = 76087, icon = C_Item.GetItemIconByID(76087) },
    { key = "flask_of_winters_bite", category = "flask", itemId = 76088, icon = C_Item.GetItemIconByID(76088) },
    { key = "alchemists_flask", category = "flask", itemId = 75525, icon = C_Item.GetItemIconByID(75525) },
    { key = "crystal_of_insanity", category = "flask", itemId = 86569, icon = C_Item.GetItemIconByID(86569) },
}

---@type buff_entry_item[]
local TBC_ENTRIES = {
    -- Flasks (a Shattrath or Flaskataur's flask counts as its base flask)
    { key = "flask_of_relentless_assault", category = "flask", itemId = 22854, icon = C_Item.GetItemIconByID(22854), variantIds = { 32901, 32765 } },
    { key = "flask_of_blinding_light", category = "flask", itemId = 22861, icon = C_Item.GetItemIconByID(22861), variantIds = { 35717 } },
    { key = "flask_of_pure_death", category = "flask", itemId = 22866, icon = C_Item.GetItemIconByID(22866), variantIds = { 35716 } },
    { key = "flask_of_fortification", category = "flask", itemId = 22851, icon = C_Item.GetItemIconByID(22851), variantIds = { 32898, 32764 } },
    { key = "flask_of_mighty_restoration", category = "flask", itemId = 22853, icon = C_Item.GetItemIconByID(22853), variantIds = { 32899, 32766 } },
    { key = "flask_of_chromatic_wonder", category = "flask", itemId = 33208, icon = C_Item.GetItemIconByID(33208) },
    { key = "flask_of_the_titans", category = "flask", itemId = 13510, icon = C_Item.GetItemIconByID(13510) },
    { key = "flask_of_distilled_wisdom", category = "flask", itemId = 13511, icon = C_Item.GetItemIconByID(13511) },
    { key = "flask_of_supreme_power", category = "flask", itemId = 13512, icon = C_Item.GetItemIconByID(13512), variantIds = { 32900, 32767 } },
    { key = "flask_of_chromatic_resistance", category = "flask", itemId = 13513, icon = C_Item.GetItemIconByID(13513) },
    -- Oils
    { key = "superior_wizard_oil", category = "oil", itemId = 22522, icon = C_Item.GetItemIconByID(22522) },
    { key = "superior_mana_oil", category = "oil", itemId = 22521, icon = C_Item.GetItemIconByID(22521) },
    { key = "wizard_oil", category = "oil", itemId = 20749, icon = C_Item.GetItemIconByID(20749), variantIds = { 20750, 20746, 20744 } },
    { key = "mana_oil", category = "oil", itemId = 20748, icon = C_Item.GetItemIconByID(20748), variantIds = { 20747, 20745 } },
    -- Weapon Buffs
    { key = "adamantite_sharpening_stone", category = "weapon_buff", itemId = 23529, icon = C_Item.GetItemIconByID(23529), variantIds = { 23528 } },
    { key = "adamantite_weightstone", category = "weapon_buff", itemId = 28421, icon = C_Item.GetItemIconByID(28421), variantIds = { 28420 } },
    { key = "elemental_sharpening_stone", category = "weapon_buff", itemId = 18262, icon = C_Item.GetItemIconByID(18262) },
    { key = "sharpening_stone", category = "weapon_buff", itemId = 12404, icon = C_Item.GetItemIconByID(12404), variantIds = { 7964, 2871, 2863, 2862 } },
    { key = "weightstone", category = "weapon_buff", itemId = 12643, icon = C_Item.GetItemIconByID(12643), variantIds = { 7965, 3241, 3240, 3239 } },
}

---@type buff_entry_item[]
local WRATH_ENTRIES = {
    -- Flasks (Jillian's Tonics count as their flask)
    { key = "flask_of_endless_rage", category = "flask", itemId = 46377, icon = C_Item.GetItemIconByID(46377), variantIds = { 45006 } },
    { key = "flask_of_pure_mojo", category = "flask", itemId = 46378, icon = C_Item.GetItemIconByID(46378), variantIds = { 45007 } },
    { key = "flask_of_stoneblood", category = "flask", itemId = 46379, icon = C_Item.GetItemIconByID(46379), variantIds = { 45008 } },
    { key = "flask_of_the_frost_wyrm", category = "flask", itemId = 46376, icon = C_Item.GetItemIconByID(46376), variantIds = { 45009 } },
    { key = "flask_of_the_north", category = "flask", itemId = 47499, icon = C_Item.GetItemIconByID(47499) },
    { key = "lesser_flask_of_toughness", category = "flask", itemId = 40079, icon = C_Item.GetItemIconByID(40079) },
    { key = "lesser_flask_of_resistance", category = "flask", itemId = 44939, icon = C_Item.GetItemIconByID(44939) },
    { key = "flask_of_relentless_assault", category = "flask", itemId = 22854, icon = C_Item.GetItemIconByID(22854), variantIds = { 32901, 32765 } },
    { key = "flask_of_blinding_light", category = "flask", itemId = 22861, icon = C_Item.GetItemIconByID(22861), variantIds = { 35717 } },
    { key = "flask_of_pure_death", category = "flask", itemId = 22866, icon = C_Item.GetItemIconByID(22866), variantIds = { 35716 } },
    { key = "flask_of_fortification", category = "flask", itemId = 22851, icon = C_Item.GetItemIconByID(22851), variantIds = { 32898, 32764 } },
    { key = "flask_of_mighty_restoration", category = "flask", itemId = 22853, icon = C_Item.GetItemIconByID(22853), variantIds = { 32899, 32766 } },
    { key = "flask_of_chromatic_wonder", category = "flask", itemId = 33208, icon = C_Item.GetItemIconByID(33208) },
    { key = "flask_of_the_titans", category = "flask", itemId = 13510, icon = C_Item.GetItemIconByID(13510) },
    { key = "flask_of_distilled_wisdom", category = "flask", itemId = 13511, icon = C_Item.GetItemIconByID(13511) },
    { key = "flask_of_supreme_power", category = "flask", itemId = 13512, icon = C_Item.GetItemIconByID(13512), variantIds = { 32900, 32767 } },
    { key = "flask_of_chromatic_resistance", category = "flask", itemId = 13513, icon = C_Item.GetItemIconByID(13513) },
    -- Oils
    { key = "exceptional_wizard_oil", category = "oil", itemId = 36900, icon = C_Item.GetItemIconByID(36900) },
    { key = "exceptional_mana_oil", category = "oil", itemId = 36899, icon = C_Item.GetItemIconByID(36899) },
    { key = "superior_wizard_oil", category = "oil", itemId = 22522, icon = C_Item.GetItemIconByID(22522) },
    { key = "superior_mana_oil", category = "oil", itemId = 22521, icon = C_Item.GetItemIconByID(22521) },
    { key = "wizard_oil", category = "oil", itemId = 20749, icon = C_Item.GetItemIconByID(20749), variantIds = { 20750, 20746, 20744 } },
    { key = "mana_oil", category = "oil", itemId = 20748, icon = C_Item.GetItemIconByID(20748), variantIds = { 20747, 20745 } },
    -- Weapon Buffs
    { key = "adamantite_sharpening_stone", category = "weapon_buff", itemId = 23529, icon = C_Item.GetItemIconByID(23529), variantIds = { 23528 } },
    { key = "adamantite_weightstone", category = "weapon_buff", itemId = 28421, icon = C_Item.GetItemIconByID(28421), variantIds = { 28420 } },
    { key = "elemental_sharpening_stone", category = "weapon_buff", itemId = 18262, icon = C_Item.GetItemIconByID(18262) },
    { key = "sharpening_stone", category = "weapon_buff", itemId = 12404, icon = C_Item.GetItemIconByID(12404), variantIds = { 7964, 2871, 2863, 2862 } },
    { key = "weightstone", category = "weapon_buff", itemId = 12643, icon = C_Item.GetItemIconByID(12643), variantIds = { 7965, 3241, 3240, 3239 } },
}

-- Classic Era: Forever's flasks, oils and stones, under the same IDs.
local BUFF_ENTRIES = ({
    retail = RETAIL_ENTRIES, forever = FOREVER_ENTRIES, mists = MISTS_ENTRIES,
    era = FOREVER_ENTRIES, tbc = TBC_ENTRIES, wrath = WRATH_ENTRIES,
})[private.ClientScope.CLIENT] or {}

---Map item IDs to their entry keys for quick lookup.
---@type table<number, string>
local ITEM_TO_ENTRY_KEY = {}
for _, entry in ipairs(BUFF_ENTRIES) do
    ITEM_TO_ENTRY_KEY[entry.itemId] = entry.key
    if entry.variantIds then
        for _, variantId in ipairs(entry.variantIds) do
            ITEM_TO_ENTRY_KEY[variantId] = entry.key
        end
    end
end

---Map spell IDs (from auraSpells) to their entry keys via item ID.
---@type table<number, string>
local SPELL_TO_ENTRY_KEY = {}
for _, cat in ipairs(BUFF_CATEGORIES) do
    if cat.auraSpells then
        for spellId, itemId in pairs(cat.auraSpells) do
            local entryKey = ITEM_TO_ENTRY_KEY[itemId]
            if entryKey then
                SPELL_TO_ENTRY_KEY[spellId] = entryKey
            end
        end
    end
end

---Lookup: category key → buff_category definition
---@type table<string, buff_category>
local CATEGORY_BY_KEY = {}
for _, cat in ipairs(BUFF_CATEGORIES) do
    CATEGORY_BY_KEY[cat.key] = cat
end

---Shaman weapon imbues, every client with them. Each rank is { spell,
---enchant }, ascending: the imbue spell and the enchant ID it puts on the
---weapon (DB2 effect 360, EffectMiscValue_0, build 1.60.1.70009; effect 54 on
---Era, TBC, Wrath and MoP, builds 1.15.9.70003, 2.5.6.69795, 3.80.2.70177,
---5.5.4.70032). A row's key is its rank-1 spell ID. MoP has one rank of each;
---Flametongue, Frostbrand and Windfury match Forever's rank 1, while its
---Rockbiter keeps the spell under another enchant, listed first. On TBC and
---Wrath a Rockbiter cast is a dummy that picks one of three enchants per rank
---by weapon speed, so each rank lists those three (SpellItemEnchantment names
---them "Rockbiter <rank>").
---One table for every client: an ID the client lacks is never known or
---reported, so the category stays empty on retail with no client check.
local IMBUES = {
    { key = 8017, ranks = { -- Rockbiter Weapon
        { spell = 8017, enchant = 3021 }, { spell = 8017, enchant = 29 }, { spell = 8017, enchant = 3022 },
        { spell = 8017, enchant = 3023 }, { spell = 8018, enchant = 6 }, { spell = 8018, enchant = 3024 },
        { spell = 8018, enchant = 3025 }, { spell = 8018, enchant = 3026 }, { spell = 8019, enchant = 1 },
        { spell = 8019, enchant = 3027 }, { spell = 8019, enchant = 3028 }, { spell = 8019, enchant = 3029 },
        { spell = 10399, enchant = 503 }, { spell = 10399, enchant = 3030 }, { spell = 10399, enchant = 3031 },
        { spell = 10399, enchant = 3032 }, { spell = 16314, enchant = 1663 }, { spell = 16314, enchant = 3033 },
        { spell = 16314, enchant = 3034 }, { spell = 16314, enchant = 3035 }, { spell = 16315, enchant = 683 },
        { spell = 16315, enchant = 3036 }, { spell = 16315, enchant = 3037 }, { spell = 16315, enchant = 3038 },
        { spell = 16316, enchant = 1664 }, { spell = 16316, enchant = 3039 }, { spell = 16316, enchant = 3040 },
        { spell = 16316, enchant = 3041 }, { spell = 25479, enchant = 2632 }, { spell = 25479, enchant = 3042 },
        { spell = 25479, enchant = 3043 }, { spell = 25479, enchant = 3044 }, { spell = 25485, enchant = 2633 },
        { spell = 25485, enchant = 3018 }, { spell = 25485, enchant = 3019 }, { spell = 25485, enchant = 3020 },
    } },
    { key = 8024, ranks = { -- Flametongue Weapon
        { spell = 8024, enchant = 5 }, { spell = 8027, enchant = 4 }, { spell = 8030, enchant = 3 },
        { spell = 16339, enchant = 523 }, { spell = 16341, enchant = 1665 }, { spell = 16342, enchant = 1666 },
        { spell = 25489, enchant = 2634 }, { spell = 58785, enchant = 3779 }, { spell = 58789, enchant = 3780 },
        { spell = 58790, enchant = 3781 },
    } },
    { key = 8033, ranks = { -- Frostbrand Weapon
        { spell = 8033, enchant = 2 }, { spell = 8038, enchant = 12 }, { spell = 10456, enchant = 524 },
        { spell = 16355, enchant = 1667 }, { spell = 16356, enchant = 1668 }, { spell = 25500, enchant = 2635 },
        { spell = 58794, enchant = 3782 }, { spell = 58795, enchant = 3783 }, { spell = 58796, enchant = 3784 },
    } },
    { key = 8232, ranks = { -- Windfury Weapon
        { spell = 8232, enchant = 283 }, { spell = 8235, enchant = 284 }, { spell = 10486, enchant = 525 },
        { spell = 16362, enchant = 1669 }, { spell = 25505, enchant = 2636 }, { spell = 58801, enchant = 3785 },
        { spell = 58803, enchant = 3786 }, { spell = 58804, enchant = 3787 },
    } },
    { key = 51730, ranks = { -- Earthliving Weapon (Wrath, MoP)
        { spell = 51730, enchant = 3345 }, { spell = 51988, enchant = 3346 }, { spell = 51991, enchant = 3347 },
        { spell = 51992, enchant = 3348 }, { spell = 51993, enchant = 3349 }, { spell = 51994, enchant = 3350 },
    } },
}

---Imbue row key → row.
local IMBUE_BY_KEY = {}
---Enchant ID → { spell, enchant, row } rank.
local IMBUE_BY_ENCHANT = {}
for _, row in ipairs(IMBUES) do
    IMBUE_BY_KEY[row.key] = row
    for _, rank in ipairs(row.ranks) do
        rank.row = row
        IMBUE_BY_ENCHANT[rank.enchant] = rank
    end
end

---The highest rank of an imbue the character has, or nil (also for a nil row,
---so a stale remembered key falls through).
---@param row table?
---@return number? spellID
local function highestKnownImbue(row)
    if not row then return nil end
    for i = #row.ranks, 1, -1 do
        local spell = row.ranks[i].spell
        if IsPlayerSpell(spell) then return spell end
    end
    return nil
end

---The highest known rank of the first imbue, in table order, the character has.
---@return number? spellID
local function firstKnownImbue()
    for _, row in ipairs(IMBUES) do
        local spell = highestKnownImbue(row)
        if spell then return spell end
    end
    return nil
end

---Rogue poisons where they are weapon enchants: WoW Forever, Era, TBC and
---Wrath. A poison is a bag item (rogue only); using it puts an enchant on the
---weapon. Each rank is { item, enchant }, ascending: the item and the enchant ID
---its use spell puts on the weapon (DB2 ItemEffect.SpellID, whose effect 360 on
---Forever, 54 elsewhere, carries the enchant in EffectMiscValue_0; builds
---1.60.1.70124, 1.15.9.70003, 2.5.6.69795, 3.80.2.70177). A row's key is its
---rank-1 item ID. Retail and MoP poisons are auras, and none of these items is
---ever found there.
local POISONS = {
    { key = 6947, ranks = { -- Instant Poison
        { item = 6947, enchant = 323 }, { item = 6949, enchant = 324 }, { item = 6950, enchant = 325 },
        { item = 8926, enchant = 623 }, { item = 8927, enchant = 624 }, { item = 8928, enchant = 625 },
        { item = 21927, enchant = 2641 }, { item = 43230, enchant = 3768 }, { item = 43231, enchant = 3769 },
    } },
    { key = 2892, ranks = { -- Deadly Poison
        { item = 2892, enchant = 7 }, { item = 2893, enchant = 8 }, { item = 8984, enchant = 626 },
        { item = 8985, enchant = 627 }, { item = 20844, enchant = 2630 }, { item = 22053, enchant = 2642 },
        { item = 22054, enchant = 2643 }, { item = 43232, enchant = 3770 }, { item = 43233, enchant = 3771 },
    } },
    { key = 3775, ranks = { -- Crippling Poison
        { item = 3775, enchant = 22 }, { item = 3776, enchant = 603 },
    } },
    { key = 5237, ranks = { -- Mind-numbing Poison
        { item = 5237, enchant = 35 }, { item = 6951, enchant = 23 }, { item = 9186, enchant = 643 },
    } },
    { key = 10918, ranks = { -- Wound Poison
        { item = 10918, enchant = 703 }, { item = 10920, enchant = 704 }, { item = 10921, enchant = 705 },
        { item = 10922, enchant = 706 }, { item = 22055, enchant = 2644 }, { item = 43234, enchant = 3772 },
        { item = 43235, enchant = 3773 },
    } },
    { key = 21835, ranks = { -- Anesthetic Poison
        { item = 21835, enchant = 2640 }, { item = 43237, enchant = 3774 },
    } },
}

---Every rank's enchant lasts 30 minutes on Forever and Era, an hour on TBC and
---Wrath (DB2 SpellItemEnchantment.Duration on Forever; the poison spells' own
---text elsewhere, as their enchant effect carries no duration).
local POISON_DURATION = (private.ClientScope.CLIENT == "tbc" or private.ClientScope.CLIENT == "wrath") and 3600 or 1800

---Poison row key → row.
local POISON_BY_KEY = {}
---Enchant ID → { item, enchant, row } rank.
local POISON_BY_ENCHANT = {}
for _, row in ipairs(POISONS) do
    POISON_BY_KEY[row.key] = row
    for _, rank in ipairs(row.ranks) do
        rank.row = row
        POISON_BY_ENCHANT[rank.enchant] = rank
    end
end

---The highest rank of a poison in the bags, or nil (also for a nil row, so a
---stale remembered key falls through).
---@param row table?
---@return number? itemID
local function bestPoisonInBags(row)
    if not row then return nil end
    for i = #row.ranks, 1, -1 do
        local item = row.ranks[i].item
        if C_Item.GetItemCount(item, false, true) > 0 then return item end
    end
    return nil
end

---The best rank in the bags of the first poison, in table order, carried.
---@return number? itemID
local function firstPoisonInBags()
    for _, row in ipairs(POISONS) do
        local item = bestPoisonInBags(row)
        if item then return item end
    end
    return nil
end

---The imbue or poison on a weapon slot and its time left in ms, or nil.  Read
---from Forever's C_Item.GetWeaponEnchantInfo, the weapon's enchants by kind:
---C_PaperDollInfo.GetTemporaryEnchantmentInfo returns nil for an imbue there
---(1.60.1, tested 2026-09-25), and so does Blizzard's AuraContainer, which
---reads it.  Every entry is matched by enchant ID whatever its enchantType, as
---Forever's own BuffFrame lists them all.  The function exists only on
---Forever, hence the presence check.  Elsewhere a hand holds one temporary
---enchant, matched the same way (an imbue on MoP; an imbue, poison, oil or
---stone on Era, TBC and Wrath); retail has none to find.
---@param invSlot number INVSLOT_MAINHAND or INVSLOT_OFFHAND
---@param byEnchant table<number, table> IMBUE_BY_ENCHANT or POISON_BY_ENCHANT
---@return table? rank, number? timeLeftMs
local function getWeaponEnchant(invSlot, byEnchant)
    if not C_Item.GetWeaponEnchantInfo then
        local info = private.compat.GetTemporaryEnchantmentInfo(invSlot)
        local rank = info and byEnchant[info.enchantID]
        if rank then return rank, info.remainingTimeMs end
        return nil
    end
    local weaponSlot = invSlot == INVSLOT_MAINHAND and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
    for _, info in ipairs(C_Item.GetWeaponEnchantInfo(weaponSlot)) do
        local rank = byEnchant[info.enchantID]
        if rank then return rank, info.timeLeft end
    end
    return nil
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local UPDATE_INTERVAL = 0.1
local elapsed_acc = 0

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

---Per-icon state (keyed by icon frame ref, NOT stored on the frame — taint prevention).
local iconCategory = {} ---@type table<Button, buff_category>
local iconSlot = {} ---@type table<Button, number> INVSLOT or 0 for aura-based
local iconIsActive = {} ---@type table<Button, boolean>
local iconAuraInstanceID = {} ---@type table<Button, number?>
local iconItemId = {} ---@type table<Button, number?>
---The show/hide half of an icon's alpha, as its own state decided it
---(hide_when_applied, suppression). Alpha writers multiply this instead of
---reading GetAlpha() back, which would latch a transient 0 for good.
local iconShown = {} ---@type table<Button, boolean>
---When an active buff's icon is due back, as GetTime() -- recorded before the
---pull, because flask, food and rune auras cannot be read in combat. nil when
---not active or not known.
local iconExpiresAt = {} ---@type table<Button, number?>

---The swipe length of the imbue on each weapon slot. The enchant call gives only
---the time left, so, as Blizzard's AuraContainer does
---(ShouldReassignForEnchantmentInfo), the length is the time left when the
---imbue is first seen, kept until the enchant ID changes or the time left goes
---up (a re-cast). Oils keep the flat WEAPON_ENCHANT_ASSUMED_DURATION.
local imbueSnap = {} ---@type table<number, {enchant: number, remaining: number, duration: number}>

---@param slot number
---@param enchant number
---@param remaining number seconds
---@return number duration seconds
local function imbueDuration(slot, enchant, remaining)
    local snap = imbueSnap[slot]
    if not snap or snap.enchant ~= enchant or remaining > snap.remaining then
        snap = { enchant = enchant, duration = remaining }
        imbueSnap[slot] = snap
    end
    snap.remaining = remaining
    return snap.duration
end

---True from the pull until combat ends. A secure button cannot move or show in
---combat, so at the pull every icon is shown in the slot it would have with all
---of them shown, an applied one at alpha 0; onUpdate reveals it in that slot
---when its recorded expiry passes.
local pinnedLayout = false

---Queued secure attribute updates for after combat. A nil type/item/spell/
---targetSlot is a queued clear.
local pendingAttributes = {} ---@type table<Button, {type: string?, item: string?, spell: number?, targetSlot: number?}>

local getSettings

---Aura data is secret during raid combat and active M+ dungeons, making
---detection unreliable (buffs always appear missing).  Hide the tracker
---entirely in these contexts.
---
---Secrecy also outlives combat: dead mid-encounter, or rezzed before the next
---pull, the player is out of combat while every aura read still returns nil,
---and a Refresh would call every flask and food missing. The second return
---says the tracker is hidden for that reason, so the caller can queue the
---Refresh that brings it back.
---@return boolean suppressed, boolean? untilSecrecyClears
local function isSuppressed()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive() then
        -- Opted in: shown even while the reads are secret, as its tooltip says.
        return not getSettings().show_in_challenge_mode
    end
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "raid" and InCombatLockdown() then
        return true
    end
    if not InCombatLockdown() and C_Secrets.ShouldAurasBeSecret() then
        return true, true
    end
    return false
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local isEntryEnabled

getSettings = function()
    return private.profile.components[comp.name]
end

local function getEnabled()
    return getSettings().enabled
end

---Get the appropriate stone item ID for a weapon in the given slot.
---@param invSlot number
---@return number? itemId
local function getStoneForSlot(invSlot)
    local weaponItemId = GetInventoryItemID("player", invSlot)
    if not weaponItemId then return nil end
    local _, _, _, _, _, classId, subclassId = C_Item.GetItemInfoInstant(weaponItemId)
    if classId ~= WEAPON_CLASS_ID then return nil end

    local category = CATEGORY_BY_KEY["weapon_buff"]
    if not category or not category.stones then return nil end
    -- The best enabled stone in the bags, else the best enabled one to show.
    local shown
    for _, stone in pairs(category.stones) do
        if stone.subClasses[subclassId] then
            for _, itemId in ipairs(stone.itemIds) do
                local entryKey = ITEM_TO_ENTRY_KEY[itemId]
                if not entryKey or isEntryEnabled(entryKey) then
                    if C_Item.GetItemCount(itemId, false, true) > 0 then return itemId end
                    shown = shown or itemId
                end
            end
        end
    end
    return shown
end

---Get the first oil item the player has in bags (respects per-item toggles).
---@param category buff_category
---@return number? itemId
local function getBestOilInBags(category)
    if not category.items then return nil end
    for _, itemId in ipairs(category.items) do
        local entryKey = ITEM_TO_ENTRY_KEY[itemId]
        if (not entryKey or isEntryEnabled(entryKey)) and C_Item.GetItemCount(itemId, false, true) > 0 then
            return itemId
        end
    end
    return nil
end

---Get the first flask/rune item the player has in bags (respects per-item toggles).
---@param category buff_category
---@return number? itemId
local function getBestAuraItemInBags(category)
    if not category.items then return nil end
    for _, itemId in ipairs(category.items) do
        local entryKey = ITEM_TO_ENTRY_KEY[itemId]
        if (not entryKey or isEntryEnabled(entryKey)) and C_Item.GetItemCount(itemId, false, true) > 0 then
            return itemId
        end
    end
    return nil
end

---Check if an offhand weapon is equipped.
---@return boolean
local function hasOffhandWeapon()
    local itemId = GetInventoryItemID("player", INVSLOT_OFFHAND)
    if not itemId then return false end
    local _, _, _, _, _, classId = C_Item.GetItemInfoInstant(itemId)
    return classId == WEAPON_CLASS_ID
end

---Check if a specific entry is enabled in tracked_buffs.
---@param entryKey string
---@return boolean
isEntryEnabled = function(entryKey)
    local val = getSettings().tracked_buffs[entryKey]
    if val == nil then return true end
    return val
end

---Check aura-based category. Returns auraInstanceID and icon if active.
---@param category buff_category
---@return number? auraInstanceID, number? icon
local function checkAuraCategory(category)
    if category.auraSpells then
        for spellId, itemId in pairs(category.auraSpells) do
            local entryKey = SPELL_TO_ENTRY_KEY[spellId]
            if not entryKey or isEntryEnabled(entryKey) then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
                if aura then
                    local icon = C_Item.GetItemIconByID(itemId) or category.fallbackIcon
                    return aura.auraInstanceID, icon
                end
            end
        end
    end
    if category.spellNames then
        for _, name in ipairs(category.spellNames) do
            local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
            if aura then
                local entryKey = SPELL_TO_ENTRY_KEY[aura.spellId]
                if not entryKey or isEntryEnabled(entryKey) then
                    return aura.auraInstanceID, aura.icon or category.fallbackIcon
                end
            end
        end
    end
    if category.spellName then
        local aura = C_UnitAuras.GetAuraDataBySpellName("player", category.spellName, "HELPFUL")
        if aura then
            return aura.auraInstanceID, aura.icon or category.fallbackIcon
        end
    end
    return nil, nil
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

    -- Overlay frame above cooldown swipe for all text elements
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(cd)
    textOverlay:SetFrameLevel(cd:GetFrameLevel() + 10)

    icon.DurationText = cd:GetRegions()
    if icon.DurationText then
        icon.DurationText:SetParent(textOverlay)
    end

    icon.Count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")

    icon:RegisterForClicks("AnyDown", "AnyUp")

    -- Install CUE tooltip on this addon-owned icon. Resolver reads icon.spellId
    -- (an imbue) or icon.itemId, both assigned by setSecureAttributes when the
    -- icon takes on a buff.
    -- isSecureClick=true so the EnableMouse formula honours settings.clickable.
    if private.Tooltip then
        private.Tooltip.Apply(icon, getSettings, function(self)
            if self.spellId then return "spell", self.spellId end
            if not self.itemId then return nil, nil end
            return "item", self.itemId
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
        icon:SetAttribute("item", attrs.item)
        icon:SetAttribute("spell", attrs.spell)
        icon:SetAttribute("target-slot", attrs.targetSlot)
    end
end

---@param icon Button
---@param itemId number?
---@param spellId number? an imbue to cast; wins over itemId
---@param targetSlot number? the weapon slot a poison is used on
local function setSecureAttributes(icon, itemId, spellId, targetSlot)
    -- icon.itemId / icon.spellId are the source of truth for the tooltip
    -- resolver — store both on every call, regardless of clickable, so the
    -- tooltip works in non-clickable mode and a pooled button never keeps the
    -- previous occupant's spell.
    icon.itemId = itemId
    icon.spellId = spellId
    if not getSettings().clickable then
        if not InCombatLockdown() then
            icon:SetAttribute("type", nil)
            icon:SetAttribute("item", nil)
            icon:SetAttribute("spell", nil)
            icon:SetAttribute("target-slot", nil)
        end
        return
    end
    -- SECURE_ACTIONS.spell casts a numeric spell by ID.
    if spellId then
        applyOrDeferAttributes(icon, { type = "spell", spell = spellId })
        return
    end
    -- An uncached name clears too: a pooled button must never keep the
    -- previous occupant's item while its tooltip already shows the new one.
    local itemName = itemId and C_Item.GetItemNameByID(itemId)
    if not itemName then
        applyOrDeferAttributes(icon, { type = nil, item = nil })
        return
    end
    -- target-slot: once the item's spell waits for an item target, the secure
    -- click uses it on that equipped slot (SecureTemplates' OnActionButtonPress,
    -- UseInventoryItem) instead of leaving the targeting cursor up.
    applyOrDeferAttributes(icon, { type = "item", item = itemName, targetSlot = targetSlot })
end

local function flushPendingAttributes()
    if InCombatLockdown() then return end
    for icon, attrs in pairs(pendingAttributes) do
        icon:SetAttribute("type", attrs.type)
        icon:SetAttribute("item", attrs.item)
        icon:SetAttribute("spell", attrs.spell)
        icon:SetAttribute("target-slot", attrs.targetSlot)
    end
    wipe(pendingAttributes)
end

---------------------------------------------------------------------------
-- Refresh logic
---------------------------------------------------------------------------

---Place one aura icon: active (desaturated, the aura's swipe) or missing (what
---a click uses).
---@param category buff_category
---@param settings table
---@param iconIndex number
---@param slot number 0 for an item-backed icon, else a spell_aura group index
---@param auraInstanceID number?
---@param texture number|string?
---@param bestItem number? the item a click uses
---@param clickSpell number? the spell a click casts
---@return number iconIndex updated index
local function placeAuraIcon(category, settings, iconIndex, slot, auraInstanceID, texture, bestItem, clickSpell)
    iconIndex = iconIndex + 1
    local icon = acquireIcon()
    orderedIcons[iconIndex] = icon

    iconCategory[icon] = category
    iconSlot[icon] = slot
    iconAuraInstanceID[icon] = auraInstanceID
    iconItemId[icon] = bestItem
    setSecureAttributes(icon, bestItem, clickSpell)
    icon.Icon:SetTexture(texture)

    if auraInstanceID then
        iconIsActive[icon] = true
        icon.Icon:SetDesaturated(true)

        local durObj = private.Util.GetAuraDurationSafe("player", auraInstanceID)
        if durObj and settings.show_duration then
            icon.Cooldown:SetCooldownFromDurationObject(durObj)
        else
            icon.Cooldown:Clear()
        end
        -- A non-nil durObj does not prove a readable remaining (updateGlows
        -- checks it the same way). Unknown means no in-combat reveal.
        local remaining = durObj and durObj:GetRemainingDuration()
        if issecretvalue(remaining) or not remaining or remaining <= 0 then
            iconExpiresAt[icon] = nil
        else
            iconExpiresAt[icon] = GetTime() + remaining
        end
    else
        iconIsActive[icon] = false
        iconExpiresAt[icon] = nil
        icon.Icon:SetDesaturated(false)
        icon.Cooldown:Clear()
    end
    icon.Cooldown:SetHideCountdownNumbers(settings.hide_cd_text == true)
    icon.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)

    -- Item count overlay
    if settings.show_count and bestItem then
        local count = C_Item.GetItemCount(bestItem, false, true)
        if count > 1 then
            icon.Count:SetText(count)
            icon.Count:Show()
        else
            icon.Count:Hide()
        end
    else
        icon.Count:Hide()
    end

    -- hide_when_applied: out of combat an active buff's icon is hidden and takes
    -- no slot. From the pull (pinnedLayout) it is shown at alpha 0 in its own
    -- slot instead, so onUpdate can reveal it there when the buff runs out.
    iconShown[icon] = not (auraInstanceID and settings.hide_when_applied)
    if not InCombatLockdown() then
        icon:SetShown(iconShown[icon] or pinnedLayout)
    end
    icon:SetAlpha(iconShown[icon] and 1 or 0)
    return iconIndex
end

---Add a single aura-based icon for the given category.
---@param category buff_category
---@param settings table
---@param iconIndex number
---@return number iconIndex updated index
local function addAuraIcon(category, settings, iconIndex)
    local auraInstanceID, auraIcon = checkAuraCategory(category)

    -- Skip if no buff active and no items in bags
    local bestItem = getBestAuraItemInBags(category)
    if not auraInstanceID and not bestItem then
        return iconIndex
    end
    local texture = auraInstanceID and (auraIcon or category.fallbackIcon)
        or (bestItem and C_Item.GetItemIconByID(bestItem)) or category.fallbackIcon
    return placeAuraIcon(category, settings, iconIndex, 0, auraInstanceID, texture, bestItem)
end

---The first spell of a group the character knows, or nil.
---@param spells number[]
---@return number?
local function firstKnownSpell(spells)
    for _, spellId in ipairs(spells) do
        if IsPlayerSpell(spellId) then return spellId end
    end
    return nil
end

---A spell_aura category (MoP rogue poisons, auras on the rogue): one icon per
---group, active when any of its spells' auras is up.  Missing, a click casts
---the group's last applied spell, else its first known one; a group the
---character knows nothing of draws no icon.
---@param category buff_category
---@param settings table
---@param iconIndex number
---@return number iconIndex updated index
local function addSpellAuraIcons(category, settings, iconIndex)
    local last = settings.poison_aura_last or {}
    settings.poison_aura_last = last
    for group, spells in ipairs(category.groups) do
        local auraInstanceID, spell
        for _, spellId in ipairs(spells) do
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
            if aura then
                auraInstanceID, spell = aura.auraInstanceID, spellId
                last[group] = spellId
                break
            end
        end
        if not spell then
            spell = last[group] and IsPlayerSpell(last[group]) and last[group] or firstKnownSpell(spells)
        end
        if spell then
            iconIndex = placeAuraIcon(category, settings, iconIndex, group, auraInstanceID,
                C_Spell.GetSpellTexture(spell), nil, spell)
        end
    end
    return iconIndex
end

---Add weapon enchant icon(s) for the given category (one per slot).
---@param category buff_category
---@param catKey string
---@param settings table
---@param iconIndex number
---@return number iconIndex updated index
local function addWeaponEnchantIcons(category, catKey, settings, iconIndex)
    -- Poisons are weapon enchants everywhere but retail (MoP's are auras and
    -- take the spell_aura path), and only a rogue can apply one (the items'
    -- AllowableClass).  Everyone else would pay a bag scan of every rank per
    -- refresh, and a non-rogue carrying traded poisons would be reminded of
    -- one (review 2026-09-30).
    if catKey == "poison" and (private.ClientScope.CLIENT == "retail"
        or select(2, UnitClass("player")) ~= "ROGUE") then
        return iconIndex
    end
    local slots = { INVSLOT_MAINHAND }
    if hasOffhandWeapon() then
        slots[2] = INVSLOT_OFFHAND
    end

    for _, slot in ipairs(slots) do
        local isActive, expiration, imbueRank, poisonRank
        if catKey == "imbue" then
            imbueRank, expiration = getWeaponEnchant(slot, IMBUE_BY_ENCHANT)
            isActive = imbueRank ~= nil
        elseif catKey == "poison" then
            poisonRank, expiration = getWeaponEnchant(slot, POISON_BY_ENCHANT)
            isActive = poisonRank ~= nil
        else
            local enchantInfo = private.compat.GetTemporaryEnchantmentInfo(slot)
            -- One temporary enchant per hand on Era, TBC and Wrath: a poison
            -- or imbue there is not this category's.
            if enchantInfo and category.enchants and not category.enchants[enchantInfo.enchantID] then
                enchantInfo = nil
            end
            isActive = enchantInfo ~= nil
            expiration = enchantInfo and enchantInfo.remainingTimeMs
        end
        expiration = expiration or 0
        local duration = WEAPON_ENCHANT_ASSUMED_DURATION

        local displayIcon = category.fallbackIcon
        local clickItem = nil
        local clickSpell = nil
        local targetSlot = nil
        local shouldAdd = true

        if catKey == "weapon_buff" then
            local stoneId = getStoneForSlot(slot)
            if not stoneId then
                shouldAdd = false
            else
                displayIcon = C_Item.GetItemIconByID(stoneId) or category.fallbackIcon
                if C_Item.GetItemCount(stoneId, false, true) > 0 then
                    clickItem = stoneId
                end
            end
        elseif catKey == "oil" then
            clickItem = getBestOilInBags(category)
            if clickItem then
                displayIcon = C_Item.GetItemIconByID(clickItem) or category.fallbackIcon
            end
        elseif catKey == "imbue" then
            -- Active: the applied rank's icon, a click re-casts that imbue.
            -- Missing: the slot's last imbue, else the first one known.
            local last = settings.imbue_last or {}
            settings.imbue_last = last
            local displaySpell
            if imbueRank then
                last[slot] = imbueRank.row.key
                clickSpell = highestKnownImbue(imbueRank.row)
                displaySpell = imbueRank.spell
                duration = imbueDuration(slot, imbueRank.enchant, expiration / 1000)
            else
                imbueSnap[slot] = nil
                clickSpell = highestKnownImbue(IMBUE_BY_KEY[last[slot]]) or firstKnownImbue()
                displaySpell = clickSpell
            end
            -- Inert for a character who knows no imbue.
            if clickSpell then
                displayIcon = C_Spell.GetSpellTexture(displaySpell)
            else
                shouldAdd = false
            end
        elseif catKey == "poison" then
            -- Active: the applied rank's icon, a click re-applies that poison's
            -- best rank in the bags. Missing: the slot's last poison, else the
            -- first one carried. Either way the click coats this weapon.
            local last = settings.poison_last or {}
            settings.poison_last = last
            if poisonRank then
                last[slot] = poisonRank.row.key
                clickItem = bestPoisonInBags(poisonRank.row)
                displayIcon = C_Item.GetItemIconByID(poisonRank.item)
                duration = math.max(POISON_DURATION, expiration / 1000)
            else
                clickItem = bestPoisonInBags(POISON_BY_KEY[last[slot]]) or firstPoisonInBags()
                displayIcon = clickItem and C_Item.GetItemIconByID(clickItem)
            end
            targetSlot = clickItem and slot
        end

        -- Skip if no active enchant and nothing to click
        if shouldAdd and not isActive and not clickItem and not clickSpell then
            shouldAdd = false
        end

        if shouldAdd then
            iconIndex = iconIndex + 1
            local icon = acquireIcon()
            orderedIcons[iconIndex] = icon

            iconCategory[icon] = category
            iconSlot[icon] = slot
            iconIsActive[icon] = isActive
            iconAuraInstanceID[icon] = nil
            iconItemId[icon] = clickItem
            setSecureAttributes(icon, clickItem, clickSpell, targetSlot)

            icon.Icon:SetTexture(displayIcon)

            if isActive then
                icon.Icon:SetDesaturated(true)
                local remainingSec = expiration / 1000
                local start = GetTime() - (duration - remainingSec)
                if settings.show_duration then
                    icon.Cooldown:SetCooldown(start, duration)
                else
                    icon.Cooldown:Clear()
                end
                iconExpiresAt[icon] = remainingSec > 0 and GetTime() + remainingSec or nil
            else
                icon.Icon:SetDesaturated(false)
                icon.Cooldown:Clear()
                iconExpiresAt[icon] = nil
            end
            icon.Cooldown:SetDrawSwipe(not settings.hide_cd_swipe)

            -- Item count overlay
            if settings.show_count and clickItem then
                local count = C_Item.GetItemCount(clickItem, false, true)
                if count > 1 then
                    icon.Count:SetText(count)
                    icon.Count:Show()
                else
                    icon.Count:Hide()
                end
            else
                icon.Count:Hide()
            end

            -- hide_when_applied: hidden while the enchant is active, shown at
            -- alpha 0 from the pull (see addAuraIcon)
            iconShown[icon] = not (isActive and settings.hide_when_applied)
            if not InCombatLockdown() then
                icon:SetShown(iconShown[icon] or pinnedLayout)
            end
            icon:SetAlpha(iconShown[icon] and 1 or 0)
        end
    end

    return iconIndex
end

---Combat-safe: hide all icons via alpha and stop glows.
---Used when entering a suppressed context during combat (can't Hide secure frames).
local function suppressIcons()
    for _, icon in ipairs(orderedIcons) do
        iconShown[icon] = false
        icon:SetAlpha(0)
        private.GlowEffect.StopAll(icon)
    end
end

---Build the ordered list of icons based on current buff state.
local function refreshAllIcons()
    local settings = getSettings()
    local tracked = settings.tracked_categories
    local inCombat = InCombatLockdown()

    -- Return all current icons to pool (SetAlpha during combat, Hide outside)
    for _, icon in ipairs(orderedIcons) do
        if inCombat then
            icon:SetAlpha(0)
        else
            icon:Hide()
        end
    end
    wipe(orderedIcons)
    poolUsedCount = 0

    local iconIndex = 0

    for _, catKey in ipairs(CATEGORY_ORDER) do
        local catEnabled = tracked[catKey]
        if catEnabled == nil then catEnabled = true end
        if catEnabled then
            local category = CATEGORY_BY_KEY[catKey]
            if category then
                if category.detection == "aura" then
                    iconIndex = addAuraIcon(category, settings, iconIndex)
                elseif category.detection == "spell_aura" then
                    iconIndex = addSpellAuraIcons(category, settings, iconIndex)
                elseif category.detection == "weapon_enchant" then
                    iconIndex = addWeaponEnchantIcons(category, catKey, settings, iconIndex)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

---@param settings table
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
        if not (collapseApplied and iconIsActive[icon]) then
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

        if collapseApplied and iconIsActive[icon] then
            -- Hidden by hide_when_applied (refreshAllIcons Hide()s it): no slot and
            -- no point. It used to be parked at alpha 0 under the first visible
            -- icon, where it could take that icon's click or tooltip.
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

        if settings.count_font then
            private.Util.ApplyFontProfile(icon.Count, settings.count_font, icon)
        end
    end

    private.Util.ApplyComponentBackground(container, settings.background)
end

---------------------------------------------------------------------------
-- Glow management
---------------------------------------------------------------------------

-- Step curve for expiring-glow threshold: maps remaining duration (seconds)
-- to alpha via EvaluateRemainingDuration. Alpha 1 inside the expiring window,
-- alpha 0 outside. Rebuilt when expiring_time changes.
---@type table?  ColorCurveObject
local expiringCurve
local expiringCurveTime = 0

---Get or rebuild the expiring threshold curve for the given time in seconds.
---@param seconds number
---@return table colorCurve
local function getExpiringCurve(seconds)
    if expiringCurve and expiringCurveTime == seconds then return expiringCurve end
    expiringCurve = C_CurveUtil.CreateColorCurve()
    expiringCurve:SetType(Enum.LuaCurveType.Step)
    expiringCurve:AddPoint(0, CreateColor(0, 0, 0, 0))
    expiringCurve:AddPoint(0.001, CreateColor(0, 0, 0, 1))
    expiringCurve:AddPoint(seconds, CreateColor(0, 0, 0, 1))
    expiringCurve:AddPoint(seconds + 0.001, CreateColor(0, 0, 0, 0))
    expiringCurveTime = seconds
    return expiringCurve
end

local function updateGlows()
    local settings = getSettings()
    local glowSettings = settings.glow
    if not glowSettings or not glowSettings.enabled then return end

    if isSuppressed() then
        for _, icon in ipairs(orderedIcons) do
            private.GlowEffect.StopAll(icon)
        end
        return
    end

    -- Only glow in dungeon and raid instances
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        for _, icon in ipairs(orderedIcons) do
            private.GlowEffect.StopAll(icon)
        end
        return
    end

    for _, icon in ipairs(orderedIcons) do
        local isActive = iconIsActive[icon]

        if not isActive then
            -- Missing buff
            if glowSettings.missing_enabled then
                private.GlowEffect.StartPulse(icon)
            end
        else
            -- Active buff — stop missing glow
            private.GlowEffect.StopPulse(icon)

            -- Check expiring threshold for aura-based
            if glowSettings.expiring_enabled and iconAuraInstanceID[icon] then
                local durObj = private.Util.GetAuraDurationSafe("player", iconAuraInstanceID[icon])
                if durObj then
                    local remaining = durObj:GetRemainingDuration()
                    if issecretvalue(remaining) then
                        -- Secret path (dungeons/combat): curve-driven wrapper alpha
                        local curve = getExpiringCurve(glowSettings.expiring_time)
                        local color = durObj:EvaluateRemainingDuration(curve)
                        private.GlowEffect.StartApproaching(icon)
                        private.GlowEffect.SetApproachingAlpha(icon, color.a)
                    else
                        -- Non-secret path (open world): direct comparison
                        if remaining and remaining > 0 and remaining <= glowSettings.expiring_time then
                            private.GlowEffect.StartApproaching(icon)
                        else
                            private.GlowEffect.StopApproaching(icon)
                        end
                    end
                end
            end
        end

    end
end

---------------------------------------------------------------------------
-- OnUpdate
---------------------------------------------------------------------------

local isSuppressedState = false

---Show an applied icon whose buff ran out in combat, in the slot the pull gave
---it, in the "missing" look addAuraIcon draws. The aura itself cannot be read
---in combat, so the expiry was recorded before the pull (iconExpiresAt). The
---state writes feed updateGlows (missing pulse) and SyncAlpha (iconShown).
---@param icon Button
local function revealExpired(icon)
    iconExpiresAt[icon] = nil
    iconIsActive[icon] = false
    iconAuraInstanceID[icon] = nil
    -- An active aura icon shows the aura's texture; the missing look is the
    -- item a click uses. Oil and stone icons show that item in both states; an
    -- imbue or poison icon shows the applied rank, so it too swaps to what a
    -- click casts or uses.
    if iconSlot[icon] == 0 then
        local itemId = iconItemId[icon]
        icon.Icon:SetTexture((itemId and C_Item.GetItemIconByID(itemId)) or iconCategory[icon].fallbackIcon)
    elseif icon.spellId then
        icon.Icon:SetTexture(C_Spell.GetSpellTexture(icon.spellId))
    elseif iconCategory[icon].key == "poison" and icon.itemId then
        icon.Icon:SetTexture(C_Item.GetItemIconByID(icon.itemId))
    end
    icon.Icon:SetDesaturated(false)
    icon.Cooldown:Clear()
    iconShown[icon] = true
    icon:SetAlpha(container:GetAlpha())
end

local function onUpdate(self, elapsed)
    elapsed_acc = elapsed_acc + elapsed
    if elapsed_acc < UPDATE_INTERVAL then return end
    elapsed_acc = 0

    local suppressed = isSuppressed()
    if suppressed and not isSuppressedState then
        isSuppressedState = true
        suppressIcons()
    elseif not suppressed and isSuppressedState then
        isSuppressedState = false
        if not InCombatLockdown() then
            comp.Refresh()
        end
    end

    if pinnedLayout and not isSuppressedState then
        local now = GetTime()
        for _, icon in ipairs(orderedIcons) do
            local expiresAt = iconExpiresAt[icon]
            if expiresAt and not iconShown[icon] and now >= expiresAt then
                revealExpired(icon)
            end
        end
    end

    updateGlows()
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------

local function onEvent(self, event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" then return end
        -- hide_when_applied is out of combat only; OnLeaveCombat's Refresh
        -- catches up with whatever changed during the fight.
        if InCombatLockdown() then return end
        comp.Refresh()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
        comp.Refresh()
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Once per batch: BAG_UPDATE fires once per bag, and each ran a full
        -- Refresh.
        comp.Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        flushPendingAttributes()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
        -- SPELLS_CHANGED: a newly learned imbue rank or imbue.
        comp.Refresh()
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_START" then
        comp.Refresh()
    end
end

---------------------------------------------------------------------------
-- Component interface
---------------------------------------------------------------------------

function comp.Initialize()
    -- Pre-cache item names for Options UI
    for _, entry in ipairs(BUFF_ENTRIES) do
        C_Item.GetItemNameByID(entry.itemId)
    end

    container = CreateFrame("Frame", "CUE_ConsumableBuffTracker", UIParent)
    container:SetSize(200, 50)

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")

    container:SetScript("OnUpdate", onUpdate)

    private.Callback.Register("OnEnterCombat", function()
        -- PLAYER_REGEN_DISABLED, before the lockdown: the last chance to lay out.
        pinnedLayout = true
        if isSuppressed() then
            suppressIcons()
            return
        end
        comp.Refresh()
    end)

    private.Callback.Register("OnZoneChange", function()
        if not InCombatLockdown() then
            comp.Refresh()
        end
    end)

    private.Callback.Register("OnLeaveCombat", function()
        pinnedLayout = false
        comp.StopAllGlows()
        flushPendingAttributes()
        comp.Refresh()
    end)

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

---A font edit this Refresh cannot apply -- in combat, or while hidden -- waits
---for the next one that draws the icons: the combat-exit pass runs without
---the font pass.
local fontsOwed = false

function comp.Refresh()
    if not container then return end
    if private.fontsDirty then fontsOwed = true end
    if InCombatLockdown() then return end

    local shouldShow = (getEnabled() or private.isEditMode) and private.Anchor.IsVisibleForComponent(comp.name)

    local suppressed, untilSecrecyClears = isSuppressed()
    if shouldShow and suppressed and not private.isEditMode then
        shouldShow = false
        -- Hidden, the container runs no OnUpdate to notice the reads coming back.
        if untilSecrecyClears then
            private.Util.RunWhenSecrecyClears(comp.name, comp.Refresh)
        end
    end

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
end

comp.ContentLayout = function()
    if not private.isEditMode then
        if isSuppressed() or private.Anchor.GetEffectiveAlpha(comp.name) == 0 then
            if InCombatLockdown() then
                container:SetAlpha(0)
                for i = 1, iconPoolSize do
                    iconPool[i]:SetAlpha(0)
                end
            else
                container:Hide()
                for i = 1, iconPoolSize do
                    iconPool[i]:Hide()
                end
            end
            return
        end
    end
    refreshAllIcons()
    applyLayout()
end

---Lightweight alpha sync for position_reference inheritance.
---SetAlpha is not protected, so this is safe to call during combat.
---Called from Anchoring.lua after lastResult is updated.
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

function comp.OnEnable()
    if container and not InCombatLockdown() then
        container:Show()
        local alpha = private.Anchor.GetEffectiveAlpha(comp.name)
        container:SetAlpha(alpha)
        comp.Refresh()
    end
end

function comp.OnDisable()
    -- Outside the combat guard: a mid-fight disable (an in-combat profile switch)
    -- cannot hide the container, so this is what stops onUpdate revealing icons.
    pinnedLayout = false
    if container and not InCombatLockdown() then
        container:Hide()
        for i = 1, iconPoolSize do
            iconPool[i]:Hide()
        end
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

function comp.GetCategoryOrder()
    return CATEGORY_ORDER
end

function comp.GetCategoryLabel(catKey)
    return CATEGORY_LABELS[catKey]
end

function comp.GetEntries()
    return BUFF_ENTRIES
end

---Get localized name for an entry (from item info).
---@param entry buff_entry_item
---@return string
function comp.GetEntryName(entry)
    return C_Item.GetItemNameByID(entry.itemId) or entry.key
end

---Debug: print detection results for all categories.
function comp.DebugDetection()
    for _, cat in ipairs(BUFF_CATEGORIES) do
        if cat.detection == "aura" then
            private.print("|cff00ff00[" .. cat.key .. "]|r aura detection:")
            if cat.auraSpells then
                for spellId, itemId in pairs(cat.auraSpells) do
                    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
                    local name = C_Item.GetItemNameByID(itemId) or "?"
                    private.print("  spellID " .. spellId .. " (" .. name .. "): " .. (aura and "FOUND auraID=" .. aura.auraInstanceID or "not found"))
                end
            end
            if cat.spellName then
                local aura = C_UnitAuras.GetAuraDataBySpellName("player", cat.spellName, "HELPFUL")
                private.print("  spellName '" .. cat.spellName .. "': " .. (aura and "FOUND auraID=" .. aura.auraInstanceID or "not found"))
            end
        elseif cat.key == "imbue" or cat.key == "poison" then
            local byEnchant = cat.key == "imbue" and IMBUE_BY_ENCHANT or POISON_BY_ENCHANT
            local function describe(slot)
                local rank, timeLeft = getWeaponEnchant(slot, byEnchant)
                if not rank then return "none" end
                local what = rank.spell and "spell " .. rank.spell or "item " .. rank.item
                return what .. " enchantID " .. rank.enchant .. " " .. math.floor(timeLeft / 1000) .. "s"
            end
            private.print("|cff00ff00[" .. cat.key .. "]|r " .. cat.key .. ": MH=" .. describe(INVSLOT_MAINHAND) .. " OH=" .. describe(INVSLOT_OFFHAND))
        elseif cat.detection == "weapon_enchant" then
            local hasMain = private.compat.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND) ~= nil
            local hasOff = private.compat.GetTemporaryEnchantmentInfo(INVSLOT_OFFHAND) ~= nil
            private.print("|cff00ff00[" .. cat.key .. "]|r weapon enchant: MH=" .. tostring(hasMain) .. " OH=" .. tostring(hasOff))
        end
    end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

private.ConsumableBuffTracker = comp
private.ComponentManager.RegisterComponent("ConsumableBuffTracker", comp)
