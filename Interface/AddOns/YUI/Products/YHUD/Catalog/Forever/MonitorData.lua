local YHUD = _G.YUI and _G.YUI.YHUD
if not YHUD then return end
local FOOD_DRINK_PRESET = {
    presetId = "food-drink",
    entryKey = "buff-aura:food-drink",
    sourceKey = "aura:preset:food-drink",
    sourceIdentity = "food-drink",
    sourceType = "yhud.player-aura",
    displaySpellID = 433,
    nameKey = "designer.preset.food_drink",
    fallbackName = "Food & Drink",
    tooltipNoteKey = "designer.preset.food_drink_tooltip",
    -- Timed seated recovery auras from 1.60.1.70938; excludes test spells and Well Fed.
    spellIDs = {
        430, 431, 432, 433, 434, 435, 833, 1127, 1129, 1131,
        1133, 1135, 1137, 2639, 5004, 5005, 5006, 5007, 6410, 7737,
        9177, 10250, 10256, 10257, 18124, 18140, 18229, 18230, 18231, 18232,
        18233, 18234, 21149, 22731, 22734, 23698, 24005, 24355, 24707, 24800,
        24869, 25660, 25695, 25696, 25697, 25700, 25701, 25702, 25703, 25886,
        25887, 25888, 25889, 25990, 26030, 26260, 26261, 26263, 26401, 26402,
        26472, 26473, 26474, 26475, 28616, 29007, 29008, 29038, 29039, 29055,
        29073, 167152, 446713, 446714, 461632, 468767, 470362, 470369, 1225769, 1225771,
        1225772, 1225774, 1226808, 1269354, 1291782, 1312719, 1330734,
    },
}

-- Verified spell identities in Forever 1.60.1.70205; spellbook checks still apply.
YHUD.BLOODLUST_PRESET = nil
YHUD.BLOOD_BOIL_WINDOW_PRESET = nil
YHUD.MonitorPresets = {
    quickItems = {
        {
            itemID = 5512,
            itemIDs = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008,
                19007, 19006, 19005, 19004, 5509, 5511, 5512 },
            fallbackKey = "designer.quick.healthstone",
        },
        { itemID = 13446, fallbackKey = "designer.quick.classic_health" },
        { itemID = 13444, fallbackKey = "designer.quick.classic_mana" },
    },
    timedBuffs = {
        FOOD_DRINK_PRESET,
    },
    timedItems = {},
    defensives = {},
    interrupts = {
        WARRIOR = { class = { 6552 } },
        PALADIN = { class = { 853 } },
        ROGUE = { class = { 1766, 408, 2094 } },
        PRIEST = { class = { 8122 } },
        MAGE = { class = { 2139 } },
    },
}

YHUD.CLASS_EXTRA_PRESETS = nil
